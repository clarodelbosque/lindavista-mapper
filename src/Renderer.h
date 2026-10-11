#pragma once

#import <Metal/Metal.h>

#include "CameraInfo.h"
#include "SceneLoader.h"

#include <optional>
#include <string>
#include <vector>

struct ViewParams {
    simd_float4x4 view;
    simd_float4x4 projection;
    simd_float2 viewportPixels;
    float pixelsPerPoint = 1.0f;
    float nearClip = 1.0f;
};

class Renderer {
public:
    bool init(id<MTLDevice> device, id<MTLCommandQueue> queue, MTLPixelFormat colorFormat,
              MTLPixelFormat depthFormat, NSUInteger sampleCount, std::string& error);

    // Uploads scene geometry. nullptr restores the placeholder: a 1 m screen on the floor.
    void setScene(const SceneData* scene);

    void begin(id<MTLRenderCommandEncoder> enc, const ViewParams& params);
    void drawStages(id<MTLRenderCommandEncoder> enc);
    void drawGuides(id<MTLRenderCommandEncoder> enc);
    void drawScreens(id<MTLRenderCommandEncoder> enc, id<MTLTexture> texture, bool flipV, bool screenBlend);
    void drawWireframe(id<MTLRenderCommandEncoder> enc);
    void drawGrid(id<MTLRenderCommandEncoder> enc);
    void drawCameraGlyphs(id<MTLRenderCommandEncoder> enc, const std::vector<CameraInfo>& cameras);

    // Reversed-Z depth of the nearest surface under a drawable pixel, if any.
    std::optional<float> pickDepth(const ViewParams& params, simd_float2 pixel, bool stages, bool guides, bool screens);

private:
    struct GpuGroup {
        id<MTLBuffer> vertices;
        id<MTLBuffer> indices;
        std::vector<MeshPart> parts;
        uint32_t indexCount = 0;
    };
    struct GpuLines {
        id<MTLBuffer> buffer;
        NSUInteger count = 0;
    };

    GpuGroup upload(const MeshGroup& group);
    GpuLines upload(const std::vector<LineSegment>& lines);
    void drawLit(id<MTLRenderCommandEncoder> enc, const GpuGroup& group);
    void drawLines(id<MTLRenderCommandEncoder> enc, const GpuLines& lines, float widthPoints,
                   id<MTLDepthStencilState> depth, float depthBias);
    void drawGeometryOnly(id<MTLRenderCommandEncoder> enc, const GpuGroup& group);

    id<MTLDevice> device_;
    id<MTLCommandQueue> queue_;
    id<MTLRenderPipelineState> litPipeline_, screenPipeline_, screenBlendPipeline_, linePipeline_, pickPipeline_;
    id<MTLDepthStencilState> depthWrite_, depthRead_, depthOff_;
    id<MTLSamplerState> sampler_;
    id<MTLTexture> pickColor_, pickDepth_;
    id<MTLBuffer> pickReadback_;

    GpuGroup screens_, stages_, guides_;
    GpuLines wireframe_, grid_, axes_;
    std::vector<LineSegment> cameraGlyph_;
    ViewParams params_;
};
