#include "SceneLoader.h"
#include "VMMath.h"

#include "ufbx.h"

#include <array>
#include <cmath>
#include <cstring>
#include <set>

namespace {

const std::string kScreenPrefix = "screen";
const std::string kGuidePrefix = "guide";

simd_float3 toFloat3(ufbx_vec3 v) { return simd_make_float3((float)v.x, (float)v.y, (float)v.z); }

// Edges are deduplicated by endpoint position so faces that don't share vertices
// (split normals/UVs) still draw each outline once.
using EdgeKey = std::array<uint32_t, 6>;

EdgeKey makeEdgeKey(simd_float3 a, simd_float3 b) {
    float fa[3] = {a.x, a.y, a.z}, fb[3] = {b.x, b.y, b.z};
    if (std::memcmp(fa, fb, sizeof(fa)) > 0) std::swap(fa, fb);
    EdgeKey key;
    std::memcpy(key.data(), fa, sizeof(fa));
    std::memcpy(key.data() + 3, fb, sizeof(fb));
    return key;
}

simd_float3 mapColor(const ufbx_material_map& color, const ufbx_material_map& factor, simd_float3 fallback) {
    simd_float3 c = color.has_value ? toFloat3(color.value_vec3) : fallback;
    float f = factor.has_value ? (float)factor.value_real : 1.0f;
    return c * f;
}

Material convertMaterial(const ufbx_material* m) {
    Material out;
    if (!m) return out;
    const ufbx_material_fbx_maps& fbx = m->fbx;
    if (fbx.diffuse_color.has_value) {
        out.diffuse = mapColor(fbx.diffuse_color, fbx.diffuse_factor, out.diffuse);
    } else if (m->pbr.base_color.has_value) {
        out.diffuse = mapColor(m->pbr.base_color, m->pbr.base_factor, out.diffuse);
    }
    out.ambient = mapColor(fbx.ambient_color, fbx.ambient_factor, out.ambient);
    out.specular = mapColor(fbx.specular_color, fbx.specular_factor, out.specular);
    out.emission = mapColor(fbx.emission_color, fbx.emission_factor, out.emission);
    if (fbx.specular_exponent.has_value) {
        out.shininess = std::fmin(std::fmax((float)fbx.specular_exponent.value_real, 0.0f), 128.0f);
    }
    return out;
}

const ufbx_material* materialForPart(const ufbx_node* node, const ufbx_mesh* mesh, uint32_t index) {
    if (index < node->materials.count) return node->materials.data[index];
    if (index < mesh->materials.count) return mesh->materials.data[index];
    return nullptr;
}

void growBounds(SceneData& scene, simd_float3 p) {
    if (!scene.hasBounds) {
        scene.boundsMin = scene.boundsMax = p;
        scene.hasBounds = true;
    } else {
        scene.boundsMin = simd_min(scene.boundsMin, p);
        scene.boundsMax = simd_max(scene.boundsMax, p);
    }
}

void appendMesh(const ufbx_node* node, MeshGroup& group, SceneData& scene) {
    const ufbx_mesh* mesh = node->mesh;
    const ufbx_matrix& toWorld = node->geometry_to_world;
    const ufbx_matrix normalToWorld = ufbx_matrix_for_normals(&toWorld);
    std::vector<uint32_t> triIndices(mesh->max_face_triangles * 3);

    for (const ufbx_mesh_part& part : mesh->material_parts) {
        if (part.num_triangles == 0) continue;

        std::vector<Vertex> vertices;
        vertices.reserve(part.num_triangles * 3);
        for (uint32_t faceIndex : part.face_indices) {
            ufbx_face face = mesh->faces.data[faceIndex];
            uint32_t numTris = ufbx_triangulate_face(triIndices.data(), triIndices.size(), mesh, face);
            for (uint32_t k = 0; k < numTris * 3; ++k) {
                uint32_t ix = triIndices[k];
                simd_float3 p = toFloat3(ufbx_transform_position(&toWorld, ufbx_get_vertex_vec3(&mesh->vertex_position, ix)));
                simd_float3 n = simd_make_float3(0, 1, 0);
                if (mesh->vertex_normal.exists) {
                    n = toFloat3(ufbx_transform_direction(&normalToWorld, ufbx_get_vertex_vec3(&mesh->vertex_normal, ix)));
                    float len = simd_length(n);
                    n = len > 1e-12f ? n / len : simd_make_float3(0, 1, 0);
                }
                ufbx_vec2 uv = mesh->vertex_uv.exists ? ufbx_get_vertex_vec2(&mesh->vertex_uv, ix) : ufbx_vec2{};
                vertices.push_back(Vertex{{p.x, p.y, p.z}, {n.x, n.y, n.z}, {(float)uv.x, (float)uv.y}});
                growBounds(scene, p);
            }
        }

        std::vector<uint32_t> indices(vertices.size());
        ufbx_vertex_stream stream = {vertices.data(), vertices.size(), sizeof(Vertex)};
        size_t uniqueCount = ufbx_generate_indices(&stream, 1, indices.data(), indices.size(), nullptr, nullptr);
        vertices.resize(uniqueCount);

        MeshPart meshPart;
        meshPart.indexOffset = (uint32_t)group.indices.size();
        meshPart.indexCount = (uint32_t)indices.size();
        meshPart.material = convertMaterial(materialForPart(node, mesh, part.index));

        uint32_t base = (uint32_t)group.vertices.size();
        group.vertices.insert(group.vertices.end(), vertices.begin(), vertices.end());
        for (uint32_t i : indices) group.indices.push_back(base + i);
        group.parts.push_back(meshPart);
    }

    // Polygon outlines (not triangle edges) for the wireframe overlay.
    std::set<EdgeKey> seen;
    for (const ufbx_face& face : mesh->faces) {
        if (face.num_indices < 2) continue;
        uint32_t edgeCount = face.num_indices == 2 ? 1 : face.num_indices;
        for (uint32_t k = 0; k < edgeCount; ++k) {
            uint32_t va = mesh->vertex_indices.data[face.index_begin + k];
            uint32_t vb = mesh->vertex_indices.data[face.index_begin + (k + 1) % face.num_indices];
            simd_float3 a = toFloat3(ufbx_transform_position(&toWorld, mesh->vertices.data[va]));
            simd_float3 b = toFloat3(ufbx_transform_position(&toWorld, mesh->vertices.data[vb]));
            if (simd_equal(a, b) || !seen.insert(makeEdgeKey(a, b)).second) continue;
            scene.wireframe.push_back(LineSegment{{a.x, a.y, a.z}, {b.x, b.y, b.z}, {1, 1, 1, 1}});
        }
    }
}

void appendCamera(const ufbx_node* node, SceneData& scene) {
    const ufbx_camera* cam = node->camera;
    if (cam->projection_mode != UFBX_PROJECTION_MODE_PERSPECTIVE) return;

    simd_float4x4 m = matrix_identity_float4x4;
    for (int c = 0; c < 4; ++c) m.columns[c].xyz = toFloat3(node->node_to_world.cols[c]);
    simd_float3 position;
    simd_quatf orientation;
    vm::decomposeRigid(m, &position, &orientation);

    CameraInfo info;
    info.name = std::string(node->name.data, node->name.length);
    info.matrix = vm::rigidTransform(position, orientation);
    info.fov = (float)cam->field_of_view_deg.y;
    info.nearClip = (float)cam->near_plane;
    info.farClip = (float)cam->far_plane;
    scene.cameras.push_back(info);
}

// Appends `src`'s vertices, indices (rebased) and parts (index offsets rebased) onto `dst`,
// the same way a single file's material parts are accumulated into one MeshGroup.
void appendMeshGroup(MeshGroup& dst, const MeshGroup& src) {
    uint32_t vertexBase = (uint32_t)dst.vertices.size();
    uint32_t indexBase = (uint32_t)dst.indices.size();
    dst.vertices.insert(dst.vertices.end(), src.vertices.begin(), src.vertices.end());
    for (uint32_t index : src.indices) dst.indices.push_back(vertexBase + index);
    for (const MeshPart& part : src.parts) {
        MeshPart copy = part;
        copy.indexOffset += indexBase;
        dst.parts.push_back(copy);
    }
}

void visit(const ufbx_node* node, SceneData& scene) {
    for (const ufbx_node* child : node->children) {
        if (child->mesh) {
            std::string name(child->name.data, child->name.length);
            switch (classifyNodeName(name)) {
                case NodeType::Screen: appendMesh(child, scene.screens, scene); break;
                case NodeType::Guide: appendMesh(child, scene.guides, scene); break;
                case NodeType::Stage: appendMesh(child, scene.stages, scene); break;
            }
        }
        if (child->camera) appendCamera(child, scene);
        visit(child, scene);
    }
}

} // namespace

NodeType classifyNodeName(const std::string& name) {
    if (name.compare(0, kScreenPrefix.size(), kScreenPrefix) == 0) return NodeType::Screen;
    if (name.compare(0, kGuidePrefix.size(), kGuidePrefix) == 0) return NodeType::Guide;
    return NodeType::Stage;
}

bool loadScene(const std::string& path, SceneData& out, std::string& error) {
    ufbx_load_opts opts = {};
    opts.target_axes = ufbx_axes_right_handed_y_up;
    opts.target_unit_meters = 0.01;
    opts.space_conversion = UFBX_SPACE_CONVERSION_MODIFY_GEOMETRY;
    opts.target_camera_axes = ufbx_axes_right_handed_y_up;
    opts.generate_missing_normals = true;
    opts.ignore_animation = true;
    opts.ignore_embedded = true;

    ufbx_error err;
    ufbx_scene* scene = ufbx_load_file(path.c_str(), &opts, &err);
    if (!scene) {
        char buffer[1024];
        ufbx_format_error(buffer, sizeof(buffer), &err);
        error = buffer;
        return false;
    }

    out = SceneData();
    out.path = path;
    visit(scene->root_node, out);
    ufbx_free_scene(scene);
    return true;
}

void mergeScenesForRender(const std::vector<const SceneData*>& scenes, SceneData& out) {
    out = SceneData();
    for (const SceneData* scene : scenes) {
        if (!scene) continue;
        appendMeshGroup(out.screens, scene->screens);
        appendMeshGroup(out.stages, scene->stages);
        appendMeshGroup(out.guides, scene->guides);
        out.wireframe.insert(out.wireframe.end(), scene->wireframe.begin(), scene->wireframe.end());
        out.cameras.insert(out.cameras.end(), scene->cameras.begin(), scene->cameras.end());
        if (!scene->hasBounds) continue;
        if (!out.hasBounds) {
            out.boundsMin = scene->boundsMin;
            out.boundsMax = scene->boundsMax;
            out.hasBounds = true;
        } else {
            out.boundsMin = simd_min(out.boundsMin, scene->boundsMin);
            out.boundsMax = simd_max(out.boundsMax, scene->boundsMax);
        }
    }
}
