#include "Camera.h"

#include <algorithm>

using namespace vm;

void GrabCamera::reset(bool emptyScene) {
    fixUpDirection = true;
    position = emptyScene ? simd_make_float3(200.0f, 105.0f, 200.0f) : simd_make_float3(300.0f, 100.0f, 300.0f);
    lookAt(simd_make_float3(0, 0, 0), simd_make_float3(0, 1, 0));
    fov = 40.0f;
    nearClip = 1.0f;
}

void GrabCamera::lookAt(simd_float3 target, simd_float3 upHint) {
    simd_float3 back = position - target;
    if (simd_length_squared(back) < 1e-12f) return;
    back = simd_normalize(back);
    simd_float3 x = simd_cross(upHint, back);
    if (simd_length_squared(x) < 1e-12f) x = simd_cross(simd_make_float3(0, 0, 1), back);
    x = simd_normalize(x);
    simd_float3 y = simd_cross(back, x);
    orientation = simd_normalize(simd_quaternion(simd_matrix(x, y, back)));
}

simd_float4x4 GrabCamera::projectionMatrix(float aspect) const {
    float f = std::clamp(fov, 0.5f, 179.0f);
    return perspectiveReversedInfinite(radians(f), std::max(aspect, 1e-4f), nearClip);
}

void GrabCamera::setTransform(const simd_float4x4& m) {
    decomposeRigid(m, &position, &orientation);
}

bool GrabCamera::matches(const simd_float4x4& m, float otherFov) const {
    if (fabsf(fov - otherFov) > 1e-3f) return false;
    simd_float3 p;
    simd_quatf q;
    decomposeRigid(m, &p, &q);
    float posTolerance = 1e-3f * std::max(1.0f, simd_length(p));
    if (simd_distance(p, position) > posTolerance) return false;
    return fabsf(simd_dot(q.vector, orientation.vector)) > 1.0f - 1e-6f;
}

void GrabCamera::rayThrough(simd_float2 point, simd_float2 viewSize, simd_float3* origin, simd_float3* dir) const {
    float tanHalf = tanf(radians(std::clamp(fov, 0.5f, 179.0f)) * 0.5f);
    float aspect = viewSize.x / std::max(viewSize.y, 1.0f);
    float ndcX = point.x / viewSize.x * 2.0f - 1.0f;
    float ndcY = 1.0f - point.y / viewSize.y * 2.0f;
    simd_float3 local = simd_make_float3(ndcX * tanHalf * aspect, ndcY * tanHalf, -1.0f);
    *origin = position;
    *dir = simd_normalize(simd_act(orientation, local));
}

simd_float3 GrabCamera::worldAtDepth(simd_float2 point, simd_float2 viewSize, float depth) const {
    simd_float3 origin, dir;
    rayThrough(point, viewSize, &origin, &dir);
    float distanceAlongView = nearClip / std::max(depth, 1e-9f);
    float cosine = simd_dot(dir, forward());
    return origin + dir * (distanceAlongView / std::max(cosine, 1e-6f));
}

bool GrabCamera::project(simd_float3 world, simd_float2 viewSize, simd_float2* point) const {
    simd_float3 local = transformPoint(viewMatrix(), world);
    if (-local.z < nearClip) return false;
    float tanHalf = tanf(radians(std::clamp(fov, 0.5f, 179.0f)) * 0.5f);
    float aspect = viewSize.x / std::max(viewSize.y, 1.0f);
    float ndcX = local.x / (-local.z * tanHalf * aspect);
    float ndcY = local.y / (-local.z * tanHalf);
    *point = simd_make_float2((ndcX + 1.0f) * 0.5f * viewSize.x, (1.0f - ndcY) * 0.5f * viewSize.y);
    return true;
}

void GrabCamera::orbit(simd_float3 pivot, simd_float2 delta, simd_float2 viewSize) {
    float radiansPerPoint = kPi / std::max(1.0f, std::min(viewSize.x, viewSize.y));
    float yaw = -delta.x * radiansPerPoint;
    float pitch = -delta.y * radiansPerPoint;

    simd_float3 yawAxis = fixUpDirection ? simd_make_float3(0, 1, 0) : up();
    simd_quatf qYaw = simd_quaternion(yaw, yawAxis);
    simd_quatf qPitch = simd_quaternion(pitch, simd_act(qYaw, right()));
    simd_quatf q = simd_mul(qPitch, qYaw);

    if (fixUpDirection) {
        // Keep the view from tipping over the poles, where "up" becomes undefined.
        simd_float3 f = simd_act(q, forward());
        if (fabsf(f.y) > 0.9995f || simd_act(q, up()).y < 0.0f) q = qYaw;
    }

    position = pivot + simd_act(q, position - pivot);
    orientation = simd_normalize(simd_mul(q, orientation));
    if (fixUpDirection) levelHorizon();
}

void GrabCamera::dolly(simd_float3 pivot, float factor) {
    position = pivot + (position - pivot) * factor;
}

void GrabCamera::pan(simd_float3 pivot, simd_float2 delta, simd_float2 viewSize) {
    float distance = std::max(simd_dot(pivot - position, forward()), nearClip);
    float worldPerPoint = 2.0f * distance * tanf(radians(std::clamp(fov, 0.5f, 179.0f)) * 0.5f) / std::max(viewSize.y, 1.0f);
    position += (-right() * delta.x + up() * delta.y) * worldPerPoint;
}

void GrabCamera::look(simd_float2 delta, simd_float2 viewSize) {
    float degreesPerPoint = 180.0f / std::max(1.0f, std::min(viewSize.x, viewSize.y));
    simd_float3 e = eulerDegrees();
    e.y -= delta.x * degreesPerPoint;  // drag right -> look right
    e.x = std::clamp(e.x - delta.y * degreesPerPoint, -89.0f, 89.0f);  // drag up -> look up
    e.z = 0.0f;  // walk mode never rolls
    setEulerDegrees(e);
}

void GrabCamera::levelHorizon() {
    simd_float3 f = forward();
    if (fabsf(f.y) > 0.9995f) return;
    simd_float3 back = -f;
    simd_float3 x = simd_normalize(simd_cross(simd_make_float3(0, 1, 0), back));
    simd_float3 y = simd_cross(back, x);
    orientation = simd_normalize(simd_quaternion(simd_matrix(x, y, back)));
}
