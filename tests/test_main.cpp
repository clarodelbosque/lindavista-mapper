#include "Camera.h"
#include "SceneLoader.h"
#include "check.h"

#include <cmath>
#include <cstdlib>
#include <string>

int g_failures = 0;

void testGpuPick(const char* scenePath);

static bool near(float a, float b, float eps = 1e-3f) { return std::fabs(a - b) <= eps; }
static bool near3(simd_float3 a, simd_float3 b, float eps = 1e-3f) { return simd_distance(a, b) <= eps; }

static simd_float3 vertexPos(const MeshGroup& g, uint32_t i) {
    const Vertex& v = g.vertices[i];
    return simd_make_float3(v.position[0], v.position[1], v.position[2]);
}

static void testClassification() {
    CHECK(classifyNodeName("screen") == NodeType::Screen);
    CHECK(classifyNodeName("screen_1") == NodeType::Screen);
    CHECK(classifyNodeName("guide.001") == NodeType::Guide);
    CHECK(classifyNodeName("Screen_1") == NodeType::Stage);
    CHECK(classifyNodeName("my_screen") == NodeType::Stage);
    CHECK(classifyNodeName("") == NodeType::Stage);
}

static void checkScene(const SceneData& s) {
    CHECK(s.screens.parts.size() == 2);
    CHECK(s.stages.parts.size() == 2);
    CHECK(s.guides.parts.size() == 1);
    CHECK(s.screens.indices.size() == 12);                // two quads
    CHECK(s.stages.indices.size() == 2 * 6 * 2 * 3);      // two boxes
    CHECK(s.hasBounds);
    CHECK(near3(s.boundsMin, simd_make_float3(-400, -20, -300), 0.05f));
    CHECK(near3(s.boundsMax, simd_make_float3(400, 250, 300), 0.05f));

    // Every screen corner keeps its authored UV: (0,0) bottom-left ... (1,1) top-right.
    // The center screen's normal faces the audience (+Z).
    bool foundBottomLeft = false, foundTopRight = false, facesAudience = false;
    for (uint32_t i = 0; i < s.screens.vertices.size(); ++i) {
        simd_float3 p = vertexPos(s.screens, i);
        const Vertex& v = s.screens.vertices[i];
        if (near3(p, simd_make_float3(-160, 30, -200), 0.05f)) {
            foundBottomLeft = near(v.uv[0], 0) && near(v.uv[1], 0);
            facesAudience = near3(simd_make_float3(v.normal[0], v.normal[1], v.normal[2]), simd_make_float3(0, 0, 1));
        }
        if (near3(p, simd_make_float3(160, 210, -200), 0.05f)) foundTopRight = near(v.uv[0], 1) && near(v.uv[1], 1);
    }
    CHECK(foundBottomLeft);
    CHECK(foundTopRight);
    CHECK(facesAudience);

    const Material& gray = s.stages.parts[0].material;
    CHECK(near3(gray.diffuse, simd_make_float3(0.45f, 0.47f, 0.52f)));
    const Material& yellow = s.guides.parts[0].material;
    CHECK(near3(yellow.emission, simd_make_float3(0.9f, 0.8f, 0.1f)));

    // Polygon outlines: box = 12 edges, quad = 4 edges; 2 boxes + 2 screens + 2 guide quads.
    CHECK(s.wireframe.size() == 2 * 12 + 2 * 4 + 2 * 4);

    CHECK(s.cameras.size() == 2);
    if (s.cameras.size() == 2) {
        const CameraInfo& front = s.cameras[0];
        CHECK(front.name == "Front");
        CHECK(near(front.fov, 40.0f));
        CHECK(near3(front.matrix.columns[3].xyz, simd_make_float3(0, 120, 600), 0.05f));
        CHECK(near3(-front.matrix.columns[2].xyz, simd_make_float3(0, 0, -1)));  // looks at the stage
        CHECK(near3(front.matrix.columns[1].xyz, simd_make_float3(0, 1, 0)));    // upright

        const CameraInfo& top = s.cameras[1];
        CHECK(top.name == "Top");
        CHECK(near(top.fov, 60.0f));
        CHECK(near3(top.matrix.columns[3].xyz, simd_make_float3(0, 900, 0), 0.05f));
        CHECK(near3(-top.matrix.columns[2].xyz, simd_make_float3(0, -1, 0)));
        CHECK(near3(top.matrix.columns[1].xyz, simd_make_float3(1, 0, 0)));
    }
}

static void testCamera() {
    GrabCamera cam;
    cam.reset();
    CHECK(near3(cam.forward(), simd_normalize(simd_make_float3(-300, -100, -300))));
    CHECK(near(cam.right().y, 0.0f));

    simd_float3 e = simd_make_float3(-20.0f, 35.0f, 10.0f);
    cam.setEulerDegrees(e);
    CHECK(near3(cam.eulerDegrees(), e, 1e-2f));

    simd_float4x4 preset = cam.transform();
    CHECK(cam.matches(preset, cam.fov));
    cam.position.x += 5.0f;
    CHECK(!cam.matches(preset, cam.fov));

    // A point picked at reversed depth maps back to its world position.
    cam.reset();
    simd_float2 view = simd_make_float2(1000, 600);
    simd_float3 target = simd_make_float3(0, 0, 0);
    simd_float2 screen;
    CHECK(cam.project(target, view, &screen));
    CHECK(near(screen.x, 500.0f, 0.05f) && near(screen.y, 300.0f, 0.05f));
    float depth = cam.nearClip / simd_distance(cam.position, target);
    CHECK(near3(cam.worldAtDepth(screen, view, depth), target, 0.05f));

    // Orbiting keeps the pivot centered and the horizon level.
    cam.orbit(target, simd_make_float2(120, 40), view);
    CHECK(cam.project(target, view, &screen));
    CHECK(near(screen.x, 500.0f, 0.1f) && near(screen.y, 300.0f, 0.1f));
    CHECK(near(cam.right().y, 0.0f));

    // Panning moves the grabbed point with the cursor.
    simd_float3 before = cam.position;
    cam.pan(target, simd_make_float2(50, 0), view);
    CHECK(cam.project(target, view, &screen));
    CHECK(near(screen.x, 550.0f, 0.5f));
    CHECK(simd_distance(before, cam.position) > 0.0f);

    // Dolly halves the distance to the pivot.
    float d0 = simd_distance(cam.position, target);
    cam.dolly(target, 0.5f);
    CHECK(near(simd_distance(cam.position, target), d0 * 0.5f, 0.01f));
}

int main(int argc, char** argv) {
    testClassification();
    testCamera();

    if (argc > 1) {
        SceneData scene;
        std::string error;
        bool ok = loadScene(argv[1], scene, error);
        CHECK(ok);
        if (ok) checkScene(scene);
        else std::printf("load error: %s\n", error.c_str());
        testGpuPick(argv[1]);

        std::string metersPath = std::string(argv[1]) + ".meters.fbx";
        std::string cmd = "python3 tools/make_test_scene.py \"" + metersPath + "\" --meters";
        if (std::system(cmd.c_str()) == 0) {
            SceneData meters;
            bool okMeters = loadScene(metersPath, meters, error);
            CHECK(okMeters);
            if (okMeters) {
                checkScene(meters);

                // Composite loading: merging two loaded files' scenes must give the union
                // of their meshes and cameras, not replace one with the other.
                SceneData combined;
                std::vector<const SceneData*> toMerge = {&scene, &meters};
                mergeScenesForRender(toMerge, combined);
                CHECK(combined.screens.parts.size() == scene.screens.parts.size() + meters.screens.parts.size());
                CHECK(combined.stages.parts.size() == scene.stages.parts.size() + meters.stages.parts.size());
                CHECK(combined.guides.parts.size() == scene.guides.parts.size() + meters.guides.parts.size());
                CHECK(combined.screens.indices.size() == scene.screens.indices.size() + meters.screens.indices.size());
                CHECK(combined.stages.indices.size() == scene.stages.indices.size() + meters.stages.indices.size());
                CHECK(combined.wireframe.size() == scene.wireframe.size() + meters.wireframe.size());
                CHECK(combined.cameras.size() == scene.cameras.size() + meters.cameras.size());
                CHECK(combined.hasBounds);
            }
        }
    }

    SceneData missing;
    std::string error;
    CHECK(!loadScene("/nonexistent/scene.fbx", missing, error));
    CHECK(!error.empty());

    if (g_failures) {
        std::printf("%d check(s) failed\n", g_failures);
        return 1;
    }
    std::printf("all tests passed\n");
    return 0;
}
