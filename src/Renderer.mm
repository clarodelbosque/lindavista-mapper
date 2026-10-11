#include "Renderer.h"
#include "VMMath.h"

#include <algorithm>

namespace {

// Compiled at runtime: the Command Line Tools ship no offline Metal compiler.
const char* kShaderSource = R"METAL(
#include <metal_stdlib>
using namespace metal;

struct Vertex { packed_float3 position; packed_float3 normal; packed_float2 uv; };
struct LineSegment { packed_float3 a; packed_float3 b; packed_float4 color; };

struct SceneUniforms { float4x4 viewProj; float4x4 view; };
struct MaterialUniforms { float4 diffuse; float4 ambient; float4 specular; float4 emission; float4 params; };
struct ScreenUniforms { float4 params; };
struct LineUniforms {
    float4x4 viewProj;
    float2 viewport;
    float halfWidth;
    float nearW;
    float depthScale;
    float pad0, pad1, pad2;
};

struct LitVaryings { float4 position [[position]]; float3 eyePos; float3 eyeNormal; };

vertex LitVaryings lit_vertex(uint vid [[vertex_id]], const device Vertex* vertices [[buffer(0)]],
                              constant SceneUniforms& u [[buffer(1)]]) {
    Vertex v = vertices[vid];
    float4 world = float4(float3(v.position), 1.0);
    LitVaryings out;
    out.position = u.viewProj * world;
    out.eyePos = (u.view * world).xyz;
    out.eyeNormal = (u.view * float4(float3(v.normal), 0.0)).xyz;
    return out;
}

// Single white headlight at the camera, like the ofLight Virtual Mapper 2.x attached to the camera,
// with the fixed-function OpenGL defaults (0.2 global ambient, infinite viewer for specular).
fragment float4 lit_fragment(LitVaryings in [[stage_in]], constant MaterialUniforms& m [[buffer(0)]]) {
    float3 l = normalize(-in.eyePos);
    float3 n = length_squared(in.eyeNormal) > 1e-12 ? normalize(in.eyeNormal) : l;
    if (dot(n, l) < 0.0) n = -n;
    float ndotl = max(dot(n, l), 0.0);
    float3 color = m.emission.rgb + m.ambient.rgb * 0.2 + m.diffuse.rgb * ndotl;
    if (ndotl > 0.0 && m.params.x > 0.0) {
        float3 h = normalize(l + float3(0.0, 0.0, 1.0));
        color += m.specular.rgb * pow(max(dot(n, h), 1e-4), m.params.x);
    }
    return float4(saturate(color), 1.0);
}

struct ScreenVaryings { float4 position [[position]]; float2 uv; };

vertex ScreenVaryings screen_vertex(uint vid [[vertex_id]], const device Vertex* vertices [[buffer(0)]],
                                    constant SceneUniforms& u [[buffer(1)]]) {
    Vertex v = vertices[vid];
    ScreenVaryings out;
    out.position = u.viewProj * float4(float3(v.position), 1.0);
    out.uv = float2(v.uv);
    return out;
}

fragment float4 screen_fragment(ScreenVaryings in [[stage_in]], texture2d<float> tex [[texture(0)]],
                                sampler smp [[sampler(0)]], constant ScreenUniforms& u [[buffer(0)]]) {
    float2 uv = in.uv;
    if (u.params.x > 0.5) uv.y = 1.0 - uv.y;
    return tex.sample(smp, uv);
}

struct LineVaryings { float4 position [[position]]; float4 color; };

// Screen-space thick lines: each instance is one segment expanded to a quad, clipped
// against the near plane first so segments passing behind the camera stay correct.
vertex LineVaryings line_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                const device LineSegment* segments [[buffer(0)]],
                                constant LineUniforms& u [[buffer(1)]]) {
    LineSegment s = segments[iid];
    float4 a = u.viewProj * float4(float3(s.a), 1.0);
    float4 b = u.viewProj * float4(float3(s.b), 1.0);
    LineVaryings out;
    out.color = float4(s.color);
    bool aBehind = a.w < u.nearW;
    bool bBehind = b.w < u.nearW;
    if (aBehind && bBehind) {
        out.position = float4(0.0, 0.0, -1.0, 1.0);
        return out;
    }
    if (aBehind) a = mix(a, b, (u.nearW - a.w) / (b.w - a.w));
    if (bBehind) b = mix(b, a, (u.nearW - b.w) / (a.w - b.w));

    float2 halfViewport = u.viewport * 0.5;
    float2 sa = a.xy / a.w * halfViewport;
    float2 sb = b.xy / b.w * halfViewport;
    float2 dir = sb - sa;
    float len = length(dir);
    dir = len > 1e-5 ? dir / len : float2(1.0, 0.0);
    float2 normal = float2(-dir.y, dir.x);

    bool atB = vid >= 2;
    float side = (vid & 1) ? 1.0 : -1.0;
    float4 p = atB ? b : a;
    float2 offset = (normal * side + dir * (atB ? 1.0 : -1.0)) * u.halfWidth;
    p.xy += offset / halfViewport * p.w;
    p.z = min(p.z * u.depthScale, p.w);
    out.position = p;
    return out;
}

fragment float4 line_fragment(LineVaryings in [[stage_in]]) { return in.color; }

struct PickVaryings { float4 position [[position]]; };

vertex PickVaryings pick_vertex(uint vid [[vertex_id]], const device Vertex* vertices [[buffer(0)]],
                                constant SceneUniforms& u [[buffer(1)]]) {
    PickVaryings out;
    out.position = u.viewProj * float4(float3(vertices[vid].position), 1.0);
    return out;
}

fragment float pick_fragment(PickVaryings in [[stage_in]]) { return in.position.z; }
)METAL";

struct SceneUniforms {
    simd_float4x4 viewProj;
    simd_float4x4 view;
};

struct MaterialUniforms {
    simd_float4 diffuse, ambient, specular, emission, params;
};

struct ScreenUniforms {
    simd_float4 params;
};

struct LineUniforms {
    simd_float4x4 viewProj;
    simd_float2 viewport;
    float halfWidth;
    float nearW;
    float depthScale;
    float pad[3];
};
static_assert(sizeof(LineUniforms) == 96, "LineUniforms must match the shader layout");

LineSegment segment(simd_float3 a, simd_float3 b, simd_float4 c) {
    return LineSegment{{a.x, a.y, a.z}, {b.x, b.y, b.z}, {c.x, c.y, c.z, c.w}};
}

// Lines on the XZ plane every `step`, spanning +-step*count, like ofDrawGridPlane rotated onto the floor.
std::vector<LineSegment> gridLines(float step, int count, simd_float4 color) {
    std::vector<LineSegment> lines;
    float extent = step * count;
    for (int i = -count; i <= count; ++i) {
        float t = step * i;
        lines.push_back(segment(simd_make_float3(t, 0, -extent), simd_make_float3(t, 0, extent), color));
        lines.push_back(segment(simd_make_float3(-extent, 0, t), simd_make_float3(extent, 0, t), color));
    }
    return lines;
}

// The camera icon from Virtual Mapper 2.x: body box, lens frustum and two film reels,
// in camera-local space (the camera looks down -Z, so the body trails behind it).
std::vector<LineSegment> cameraGlyphLines() {
    std::vector<LineSegment> lines;
    const simd_float4 white = {1, 1, 1, 1};
    auto boxEdges = [&](const simd_float3 (&v)[8]) {
        const int edges[12][2] = {{0, 1}, {2, 3}, {4, 5}, {6, 7}, {0, 2}, {1, 3},
                                  {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}};
        for (auto& e : edges) lines.push_back(segment(v[e[0]], v[e[1]], white));
    };
    const simd_float3 body[8] = {{12.5f, 12.5f, 12.5f},   {12.5f, 12.5f, 62.5f},   {-12.5f, 12.5f, 12.5f},
                                 {-12.5f, 12.5f, 62.5f},  {12.5f, -12.5f, 12.5f},  {12.5f, -12.5f, 62.5f},
                                 {-12.5f, -12.5f, 12.5f}, {-12.5f, -12.5f, 62.5f}};
    const simd_float3 lens[8] = {{11, 11, 0},   {3.75f, 3.75f, 12.5f},   {-11, 11, 0},   {-3.75f, 3.75f, 12.5f},
                                 {11, -11, 0},  {3.75f, -3.75f, 12.5f},  {-11, -11, 0},  {-3.75f, -3.75f, 12.5f}};
    boxEdges(body);
    boxEdges(lens);
    const int segments = 32;
    for (float center : {25.0f, 50.0f}) {
        for (int i = 0; i < segments; ++i) {
            float a0 = 2 * vm::kPi * i / segments, a1 = 2 * vm::kPi * (i + 1) / segments;
            simd_float3 p0 = {0, 25 + 12.5f * sinf(a0), center + 12.5f * cosf(a0)};
            simd_float3 p1 = {0, 25 + 12.5f * sinf(a1), center + 12.5f * cosf(a1)};
            lines.push_back(segment(p0, p1, white));
        }
    }
    return lines;
}

MeshGroup placeholderScreen() {
    MeshGroup g;
    g.vertices = {
        {{-50, 0, 50}, {0, 1, 0}, {0, 0}},
        {{50, 0, 50}, {0, 1, 0}, {1, 0}},
        {{50, 0, -50}, {0, 1, 0}, {1, 1}},
        {{-50, 0, -50}, {0, 1, 0}, {0, 1}},
    };
    g.indices = {0, 1, 2, 0, 2, 3};
    g.parts.push_back(MeshPart{0, 6, Material()});
    return g;
}

MTLRenderPipelineColorAttachmentDescriptor* configureBlend(MTLRenderPipelineDescriptor* d, MTLBlendFactor srcRGB,
                                                           MTLBlendFactor dstRGB, MTLBlendFactor srcA, MTLBlendFactor dstA) {
    MTLRenderPipelineColorAttachmentDescriptor* c = d.colorAttachments[0];
    c.blendingEnabled = YES;
    c.sourceRGBBlendFactor = srcRGB;
    c.destinationRGBBlendFactor = dstRGB;
    c.sourceAlphaBlendFactor = srcA;
    c.destinationAlphaBlendFactor = dstA;
    return c;
}

} // namespace

bool Renderer::init(id<MTLDevice> device, id<MTLCommandQueue> queue, MTLPixelFormat colorFormat,
                    MTLPixelFormat depthFormat, NSUInteger sampleCount, std::string& error) {
    device_ = device;
    queue_ = queue;

    NSError* err = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:@(kShaderSource) options:nil error:&err];
    if (!library) {
        error = std::string("Shader compilation failed: ") + err.localizedDescription.UTF8String;
        return false;
    }

    auto makePipeline = [&](NSString* vs, NSString* fs, void (^configure)(MTLRenderPipelineDescriptor*)) -> id<MTLRenderPipelineState> {
        MTLRenderPipelineDescriptor* d = [MTLRenderPipelineDescriptor new];
        d.vertexFunction = [library newFunctionWithName:vs];
        d.fragmentFunction = [library newFunctionWithName:fs];
        d.colorAttachments[0].pixelFormat = colorFormat;
        d.depthAttachmentPixelFormat = depthFormat;
        d.rasterSampleCount = sampleCount;
        if (configure) configure(d);
        NSError* pipelineError = nil;
        id<MTLRenderPipelineState> state = [device newRenderPipelineStateWithDescriptor:d error:&pipelineError];
        if (!state) error = std::string("Pipeline creation failed: ") + pipelineError.localizedDescription.UTF8String;
        return state;
    };

    litPipeline_ = makePipeline(@"lit_vertex", @"lit_fragment", nil);
    screenPipeline_ = makePipeline(@"screen_vertex", @"screen_fragment", ^(MTLRenderPipelineDescriptor* d) {
        configureBlend(d, MTLBlendFactorSourceAlpha, MTLBlendFactorOneMinusSourceAlpha, MTLBlendFactorOne,
                       MTLBlendFactorOneMinusSourceAlpha);
    });
    screenBlendPipeline_ = makePipeline(@"screen_vertex", @"screen_fragment", ^(MTLRenderPipelineDescriptor* d) {
        configureBlend(d, MTLBlendFactorOneMinusDestinationColor, MTLBlendFactorOne,
                       MTLBlendFactorOneMinusDestinationColor, MTLBlendFactorOne);
    });
    linePipeline_ = makePipeline(@"line_vertex", @"line_fragment", ^(MTLRenderPipelineDescriptor* d) {
        configureBlend(d, MTLBlendFactorSourceAlpha, MTLBlendFactorOneMinusSourceAlpha, MTLBlendFactorOne,
                       MTLBlendFactorOneMinusSourceAlpha);
    });
    pickPipeline_ = makePipeline(@"pick_vertex", @"pick_fragment", ^(MTLRenderPipelineDescriptor* d) {
        d.colorAttachments[0].pixelFormat = MTLPixelFormatR32Float;
        d.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        d.rasterSampleCount = 1;
    });
    if (!litPipeline_ || !screenPipeline_ || !screenBlendPipeline_ || !linePipeline_ || !pickPipeline_) return false;

    auto makeDepth = [&](MTLCompareFunction compare, BOOL write) {
        MTLDepthStencilDescriptor* d = [MTLDepthStencilDescriptor new];
        d.depthCompareFunction = compare;
        d.depthWriteEnabled = write;
        return [device newDepthStencilStateWithDescriptor:d];
    };
    depthWrite_ = makeDepth(MTLCompareFunctionGreater, YES);
    depthRead_ = makeDepth(MTLCompareFunctionGreaterEqual, NO);
    depthOff_ = makeDepth(MTLCompareFunctionAlways, NO);

    MTLSamplerDescriptor* s = [MTLSamplerDescriptor new];
    s.minFilter = MTLSamplerMinMagFilterLinear;
    s.magFilter = MTLSamplerMinMagFilterLinear;
    s.sAddressMode = MTLSamplerAddressModeClampToEdge;
    s.tAddressMode = MTLSamplerAddressModeClampToEdge;
    sampler_ = [device newSamplerStateWithDescriptor:s];

    MTLTextureDescriptor* pc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float
                                                                                  width:1 height:1 mipmapped:NO];
    pc.usage = MTLTextureUsageRenderTarget;
    pc.storageMode = MTLStorageModePrivate;
    pickColor_ = [device newTextureWithDescriptor:pc];
    MTLTextureDescriptor* pd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                  width:1 height:1 mipmapped:NO];
    pd.usage = MTLTextureUsageRenderTarget;
    pd.storageMode = MTLStorageModePrivate;
    pickDepth_ = [device newTextureWithDescriptor:pd];
    pickReadback_ = [device newBufferWithLength:sizeof(float) options:MTLResourceStorageModeShared];

    grid_ = upload(gridLines(100.0f, 10, simd_make_float4(0.502f, 0.502f, 0.502f, 1.0f)));
    axes_ = upload(std::vector<LineSegment>{
        segment(simd_make_float3(0, 0, 0), simd_make_float3(400, 0, 0), simd_make_float4(1, 0, 0, 1)),
        segment(simd_make_float3(0, 0, 0), simd_make_float3(0, 400, 0), simd_make_float4(0, 1, 0, 1)),
        segment(simd_make_float3(0, 0, 0), simd_make_float3(0, 0, 400), simd_make_float4(0, 0, 1, 1)),
    });
    cameraGlyph_ = cameraGlyphLines();
    setScene(nullptr);
    return true;
}

Renderer::GpuGroup Renderer::upload(const MeshGroup& group) {
    GpuGroup g;
    if (group.empty()) return g;
    g.vertices = [device_ newBufferWithBytes:group.vertices.data()
                                      length:group.vertices.size() * sizeof(Vertex)
                                     options:MTLResourceStorageModeShared];
    g.indices = [device_ newBufferWithBytes:group.indices.data()
                                     length:group.indices.size() * sizeof(uint32_t)
                                    options:MTLResourceStorageModeShared];
    g.parts = group.parts;
    g.indexCount = (uint32_t)group.indices.size();
    return g;
}

Renderer::GpuLines Renderer::upload(const std::vector<LineSegment>& lines) {
    GpuLines l;
    if (lines.empty()) return l;
    l.buffer = [device_ newBufferWithBytes:lines.data() length:lines.size() * sizeof(LineSegment)
                                   options:MTLResourceStorageModeShared];
    l.count = lines.size();
    return l;
}

void Renderer::setScene(const SceneData* scene) {
    if (scene) {
        screens_ = upload(scene->screens);
        stages_ = upload(scene->stages);
        guides_ = upload(scene->guides);
        wireframe_ = upload(scene->wireframe);
    } else {
        screens_ = upload(placeholderScreen());
        stages_ = GpuGroup();
        guides_ = GpuGroup();
        wireframe_ = upload(gridLines(10.0f, 5, simd_make_float4(1, 1, 1, 1)));
    }
}

void Renderer::begin(id<MTLRenderCommandEncoder> enc, const ViewParams& params) {
    params_ = params;
    SceneUniforms u = {simd_mul(params.projection, params.view), params.view};
    [enc setCullMode:MTLCullModeNone];
    [enc setVertexBytes:&u length:sizeof(u) atIndex:1];
}

void Renderer::drawLit(id<MTLRenderCommandEncoder> enc, const GpuGroup& group) {
    if (!group.indexCount) return;
    [enc setRenderPipelineState:litPipeline_];
    [enc setDepthStencilState:depthWrite_];
    [enc setVertexBuffer:group.vertices offset:0 atIndex:0];
    for (const MeshPart& part : group.parts) {
        const Material& m = part.material;
        MaterialUniforms mu = {simd_make_float4(m.diffuse, 1), simd_make_float4(m.ambient, 1),
                               simd_make_float4(m.specular, 1), simd_make_float4(m.emission, 1),
                               simd_make_float4(m.shininess, 0, 0, 0)};
        [enc setFragmentBytes:&mu length:sizeof(mu) atIndex:0];
        [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:part.indexCount indexType:MTLIndexTypeUInt32
                       indexBuffer:group.indices indexBufferOffset:part.indexOffset * sizeof(uint32_t)];
    }
}

void Renderer::drawStages(id<MTLRenderCommandEncoder> enc) { drawLit(enc, stages_); }
void Renderer::drawGuides(id<MTLRenderCommandEncoder> enc) { drawLit(enc, guides_); }

void Renderer::drawScreens(id<MTLRenderCommandEncoder> enc, id<MTLTexture> texture, bool flipV, bool screenBlend) {
    if (!screens_.indexCount || !texture) return;
    ScreenUniforms su = {simd_make_float4(flipV ? 1.0f : 0.0f, 0, 0, 0)};
    [enc setRenderPipelineState:screenBlend ? screenBlendPipeline_ : screenPipeline_];
    [enc setDepthStencilState:screenBlend ? depthRead_ : depthWrite_];
    [enc setVertexBuffer:screens_.vertices offset:0 atIndex:0];
    [enc setFragmentTexture:texture atIndex:0];
    [enc setFragmentSamplerState:sampler_ atIndex:0];
    [enc setFragmentBytes:&su length:sizeof(su) atIndex:0];
    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:screens_.indexCount indexType:MTLIndexTypeUInt32
                   indexBuffer:screens_.indices indexBufferOffset:0];
}

void Renderer::drawLines(id<MTLRenderCommandEncoder> enc, const GpuLines& lines, float widthPoints,
                         id<MTLDepthStencilState> depth, float depthBias) {
    if (!lines.count) return;
    LineUniforms lu = {};
    lu.viewProj = simd_mul(params_.projection, params_.view);
    lu.viewport = params_.viewportPixels;
    lu.halfWidth = 0.5f * widthPoints * params_.pixelsPerPoint;
    lu.nearW = params_.nearClip * 1.001f;
    lu.depthScale = 1.0f + depthBias;
    [enc setRenderPipelineState:linePipeline_];
    [enc setDepthStencilState:depth];
    [enc setVertexBuffer:lines.buffer offset:0 atIndex:0];
    [enc setVertexBytes:&lu length:sizeof(lu) atIndex:1];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:lines.count];
    SceneUniforms u = {lu.viewProj, params_.view};
    [enc setVertexBytes:&u length:sizeof(u) atIndex:1];
}

void Renderer::drawWireframe(id<MTLRenderCommandEncoder> enc) { drawLines(enc, wireframe_, 2.0f, depthRead_, 2e-3f); }

void Renderer::drawGrid(id<MTLRenderCommandEncoder> enc) {
    drawLines(enc, axes_, 2.0f, depthRead_, 1e-3f);
    drawLines(enc, grid_, 1.0f, depthRead_, 1e-3f);
}

void Renderer::drawCameraGlyphs(id<MTLRenderCommandEncoder> enc, const std::vector<CameraInfo>& cameras) {
    if (cameras.empty()) return;
    std::vector<LineSegment> lines;
    lines.reserve(cameras.size() * cameraGlyph_.size());
    const simd_float4 color = {1, 1, 1, 192.0f / 255.0f};
    for (const CameraInfo& cam : cameras) {
        for (const LineSegment& s : cameraGlyph_) {
            simd_float3 a = vm::transformPoint(cam.matrix, simd_make_float3(s.a[0], s.a[1], s.a[2]));
            simd_float3 b = vm::transformPoint(cam.matrix, simd_make_float3(s.b[0], s.b[1], s.b[2]));
            lines.push_back(segment(a, b, color));
        }
    }
    drawLines(enc, upload(lines), 1.0f, depthOff_, 0.0f);
}

void Renderer::drawGeometryOnly(id<MTLRenderCommandEncoder> enc, const GpuGroup& group) {
    if (!group.indexCount) return;
    [enc setVertexBuffer:group.vertices offset:0 atIndex:0];
    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:group.indexCount indexType:MTLIndexTypeUInt32
                   indexBuffer:group.indices indexBufferOffset:0];
}

std::optional<float> Renderer::pickDepth(const ViewParams& params, simd_float2 pixel, bool stages, bool guides,
                                         bool screens) {
    simd_float2 size = params.viewportPixels;
    if (size.x < 1 || size.y < 1) return std::nullopt;
    simd_float2 ndc = {(pixel.x + 0.5f) / size.x * 2.0f - 1.0f, 1.0f - (pixel.y + 0.5f) / size.y * 2.0f};

    // Zoom the projection so the single pixel under the cursor fills the 1x1 target.
    simd_float4x4 zoom = matrix_identity_float4x4;
    zoom.columns[0].x = size.x;
    zoom.columns[1].y = size.y;
    zoom.columns[3].x = -ndc.x * size.x;
    zoom.columns[3].y = -ndc.y * size.y;
    SceneUniforms u = {simd_mul(zoom, simd_mul(params.projection, params.view)), params.view};

    MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = pickColor_;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.depthAttachment.texture = pickDepth_;
    pass.depthAttachment.loadAction = MTLLoadActionClear;
    pass.depthAttachment.clearDepth = 0.0;
    pass.depthAttachment.storeAction = MTLStoreActionDontCare;

    id<MTLCommandBuffer> cb = [queue_ commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pass];
    [enc setRenderPipelineState:pickPipeline_];
    [enc setDepthStencilState:depthWrite_];
    [enc setCullMode:MTLCullModeNone];
    [enc setVertexBytes:&u length:sizeof(u) atIndex:1];
    if (stages) drawGeometryOnly(enc, stages_);
    if (guides) drawGeometryOnly(enc, guides_);
    if (screens) drawGeometryOnly(enc, screens_);
    [enc endEncoding];

    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit copyFromTexture:pickColor_ sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake(1, 1, 1) toBuffer:pickReadback_ destinationOffset:0
      destinationBytesPerRow:sizeof(float) destinationBytesPerImage:sizeof(float)];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];

    float depth = *(const float*)pickReadback_.contents;
    if (depth > 0.0f) return depth;
    return std::nullopt;
}
