#pragma once

#include <simd/simd.h>
#include <cmath>

namespace vm {

constexpr float kPi = 3.14159265358979323846f;

inline float radians(float deg) { return deg * (kPi / 180.0f); }
inline float degrees(float rad) { return rad * (180.0f / kPi); }

inline simd_float4x4 rigidTransform(simd_float3 position, simd_quatf orientation) {
    simd_float4x4 m = simd_matrix4x4(orientation);
    m.columns[3] = simd_make_float4(position, 1.0f);
    return m;
}

// Right-handed view space looking down -Z, Metal clip space, reversed depth with an
// infinite far plane: depth = nearZ / distance, so larger values are closer.
inline simd_float4x4 perspectiveReversedInfinite(float fovyRadians, float aspect, float nearZ) {
    float f = 1.0f / tanf(fovyRadians * 0.5f);
    simd_float4x4 m = {{
        {f / aspect, 0.0f, 0.0f, 0.0f},
        {0.0f, f, 0.0f, 0.0f},
        {0.0f, 0.0f, 0.0f, -1.0f},
        {0.0f, 0.0f, nearZ, 0.0f},
    }};
    return m;
}

inline simd_float3 transformPoint(const simd_float4x4& m, simd_float3 p) {
    return simd_mul(m, simd_make_float4(p, 1.0f)).xyz;
}

inline simd_float3 transformDirection(const simd_float4x4& m, simd_float3 d) {
    return simd_mul(m, simd_make_float4(d, 0.0f)).xyz;
}

// Splits an affine matrix into translation and a proper rotation, discarding scale/shear.
// The -Z (view) axis is preserved exactly so imported cameras keep their aim.
inline void decomposeRigid(const simd_float4x4& m, simd_float3* position, simd_quatf* orientation) {
    simd_float3 y = m.columns[1].xyz;
    simd_float3 z = m.columns[2].xyz;
    if (simd_length_squared(z) < 1e-12f) z = simd_make_float3(0, 0, 1);
    z = simd_normalize(z);
    simd_float3 x = simd_cross(y, z);
    if (simd_length_squared(x) < 1e-12f) {
        simd_float3 ref = fabsf(z.y) < 0.99f ? simd_make_float3(0, 1, 0) : simd_make_float3(1, 0, 0);
        x = simd_cross(ref, z);
    }
    x = simd_normalize(x);
    y = simd_cross(z, x);
    *position = m.columns[3].xyz;
    *orientation = simd_normalize(simd_quaternion(simd_matrix(x, y, z)));
}

// Euler angles in degrees for R = Ry(yaw) * Rx(pitch) * Rz(roll), returned as (pitch, yaw, roll).
inline simd_float3 eulerFromQuat(simd_quatf q) {
    simd_float3x3 r = simd_matrix3x3(q);
    float r12 = r.columns[2].y;
    float pitch = asinf(fmaxf(-1.0f, fminf(1.0f, -r12)));
    float yaw, roll;
    if (fabsf(r12) < 0.99999f) {
        yaw = atan2f(r.columns[2].x, r.columns[2].z);
        roll = atan2f(r.columns[0].y, r.columns[1].y);
    } else {
        yaw = atan2f(-r.columns[0].z, r.columns[0].x);
        roll = 0.0f;
    }
    return simd_make_float3(degrees(pitch), degrees(yaw), degrees(roll));
}

inline simd_quatf quatFromEuler(simd_float3 eulerDeg) {
    simd_quatf qx = simd_quaternion(radians(eulerDeg.x), simd_make_float3(1, 0, 0));
    simd_quatf qy = simd_quaternion(radians(eulerDeg.y), simd_make_float3(0, 1, 0));
    simd_quatf qz = simd_quaternion(radians(eulerDeg.z), simd_make_float3(0, 0, 1));
    return simd_normalize(simd_mul(qy, simd_mul(qx, qz)));
}

} // namespace vm
