#pragma once

#include "VMMath.h"

// Perspective camera with "grab" navigation: orbit, dolly and pan all act around a
// world-space pivot, normally the point under the cursor when the drag started.
class GrabCamera {
public:
    simd_float3 position = {300.0f, 100.0f, 300.0f};
    simd_quatf orientation = simd_quaternion(0.0f, 0.0f, 0.0f, 1.0f);
    float fov = 40.0f;      // vertical, degrees
    float nearClip = 1.0f;  // centimeters
    bool fixUpDirection = true;

    // The default view: a wide one for stage scenes, or, with `emptyScene` (nothing loaded,
    // so only the 160 x 90 cm placeholder screen), a closer one that frames that screen.
    void reset(bool emptyScene = false);
    void lookAt(simd_float3 target, simd_float3 up);

    simd_float4x4 transform() const { return vm::rigidTransform(position, orientation); }
    simd_float4x4 viewMatrix() const { return simd_inverse(transform()); }
    simd_float4x4 projectionMatrix(float aspect) const;
    void setTransform(const simd_float4x4& m);
    bool matches(const simd_float4x4& m, float otherFov) const;

    simd_float3 right() const { return simd_act(orientation, simd_make_float3(1, 0, 0)); }
    simd_float3 up() const { return simd_act(orientation, simd_make_float3(0, 1, 0)); }
    simd_float3 forward() const { return simd_act(orientation, simd_make_float3(0, 0, -1)); }

    simd_float3 eulerDegrees() const { return vm::eulerFromQuat(orientation); }
    void setEulerDegrees(simd_float3 e) { orientation = vm::quatFromEuler(e); }

    // View-space helpers. Points are in view units (points) with a top-left origin.
    void rayThrough(simd_float2 point, simd_float2 viewSize, simd_float3* origin, simd_float3* dir) const;
    simd_float3 worldAtDepth(simd_float2 point, simd_float2 viewSize, float depth) const;
    bool project(simd_float3 world, simd_float2 viewSize, simd_float2* point) const;

    void orbit(simd_float3 pivot, simd_float2 delta, simd_float2 viewSize);
    void dolly(simd_float3 pivot, float factor);
    void pan(simd_float3 pivot, simd_float2 delta, simd_float2 viewSize);

    // Walk mode: rotates the camera in place (yaw/pitch around its own position, not a
    // scene pivot). Pitch is clamped to avoid flipping through the poles, and roll is
    // always reset to zero -- there is no "up/down is sideways" case in walk mode.
    void look(simd_float2 delta, simd_float2 viewSize);

private:
    void levelHorizon();
};
