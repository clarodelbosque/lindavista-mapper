#include "Camera.h"
#include "Renderer.h"
#include "SceneLoader.h"
#include "check.h"

#import <Metal/Metal.h>

static bool near3(simd_float3 a, simd_float3 b, float eps) { return simd_distance(a, b) <= eps; }

// Picks points through the Front camera of the generated test scene and checks that the
// GPU depth pick unprojects back onto the surfaces that were aimed at.
void testGpuPick(const char* scenePath) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        std::printf("SKIP gpu pick: no Metal device\n");
        return;
    }
    Renderer renderer;
    std::string error;
    bool ok = renderer.init(device, [device newCommandQueue], MTLPixelFormatBGRA8Unorm, MTLPixelFormatDepth32Float, 4, error);
    CHECK(ok);
    if (!ok) {
        std::printf("renderer init: %s\n", error.c_str());
        return;
    }
    SceneData scene;
    CHECK(loadScene(scenePath, scene, error));
    renderer.setScene(&scene);

    GrabCamera cam;
    cam.position = simd_make_float3(0, 120, 600);
    cam.orientation = simd_quaternion(0.0f, 0.0f, 0.0f, 1.0f);
    cam.fov = 40;
    const simd_float2 view = simd_make_float2(1000, 600);
    const float scale = 2.0f;
    ViewParams params;
    params.view = cam.viewMatrix();
    params.projection = cam.projectionMatrix(view.x / view.y);
    params.viewportPixels = view * scale;
    params.pixelsPerPoint = scale;
    params.nearClip = cam.nearClip;

    auto pickAt = [&](simd_float3 target, bool stages, bool guides, bool screens, simd_float3* hit) {
        simd_float2 point;
        if (!cam.project(target, view, &point)) return false;
        std::optional<float> depth = renderer.pickDepth(params, point * scale, stages, guides, screens);
        if (!depth) return false;
        *hit = cam.worldAtDepth(point, view, *depth);
        return true;
    };

    simd_float3 hit;
    CHECK(pickAt(simd_make_float3(0, 120, -200), true, true, true, &hit));
    CHECK(near3(hit, simd_make_float3(0, 120, -200), 1.0f));  // center screen

    CHECK(pickAt(simd_make_float3(260, 125, -100), true, true, true, &hit));
    CHECK(near3(hit, simd_make_float3(260, 125, -100), 1.0f));  // pillar front face

    CHECK(pickAt(simd_make_float3(100, 0, 150), true, true, true, &hit));
    CHECK(near3(hit, simd_make_float3(100, 0, 150), 1.0f));  // floor top

    CHECK(pickAt(simd_make_float3(0, 24, -199), true, true, true, &hit));
    CHECK(near3(hit, simd_make_float3(0, 24, -199), 1.0f));  // guide bar in front of the screen

    // Hidden layers are not pickable: without screens the center ray hits nothing.
    CHECK(!pickAt(simd_make_float3(0, 120, -200), true, true, false, &hit));
    // Without guides, the same pixel falls through the guide bar (to whatever lies behind it, if anything).
    bool behind = pickAt(simd_make_float3(0, 24, -199), true, false, true, &hit);
    CHECK(!behind || hit.z < -199.5f);
}
