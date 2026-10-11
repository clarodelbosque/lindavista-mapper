#pragma once

#include "CameraInfo.h"

#include <simd/simd.h>
#include <cstdint>
#include <string>
#include <vector>

struct Vertex {
    float position[3];
    float normal[3];
    float uv[2];
};
static_assert(sizeof(Vertex) == 32, "Vertex layout is shared with the Metal shaders");

struct LineSegment {
    float a[3];
    float b[3];
    float color[4];
};
static_assert(sizeof(LineSegment) == 40, "LineSegment layout is shared with the Metal shaders");

struct Material {
    simd_float3 diffuse = {0.8f, 0.8f, 0.8f};
    simd_float3 ambient = {0.2f, 0.2f, 0.2f};
    simd_float3 specular = {0.0f, 0.0f, 0.0f};
    simd_float3 emission = {0.0f, 0.0f, 0.0f};
    float shininess = 0.0f;
};

struct MeshPart {
    uint32_t indexOffset = 0;
    uint32_t indexCount = 0;
    Material material;
};

struct MeshGroup {
    std::vector<Vertex> vertices;
    std::vector<uint32_t> indices;
    std::vector<MeshPart> parts;
    bool empty() const { return indices.empty(); }
};

enum class NodeType { Screen, Stage, Guide };

// Meshes named "screen*" receive the source texture, "guide*" are toggleable guides,
// everything else is stage geometry. Matching is case-sensitive, as in Virtual Mapper 2.x.
NodeType classifyNodeName(const std::string& name);

struct SceneData {
    std::string path;
    MeshGroup screens, stages, guides;
    std::vector<LineSegment> wireframe;
    std::vector<CameraInfo> cameras;
    simd_float3 boundsMin = {0, 0, 0};
    simd_float3 boundsMax = {0, 0, 0};
    bool hasBounds = false;
};

// Loads an FBX (or OBJ) scene converted to Y-up, right-handed, centimeter units, with all
// geometry baked into world space. Returns false and fills `error` on failure.
bool loadScene(const std::string& path, SceneData& out, std::string& error);

// Merges several already-loaded scenes' geometry, wireframe, camera lists and bounds into
// one SceneData, for rendering (or inspecting) multiple loaded FBX files together as a
// single scene. `out` is reset first; its `path` is left empty since the result spans
// multiple files. Null entries in `scenes` are skipped.
void mergeScenesForRender(const std::vector<const SceneData*>& scenes, SceneData& out);
