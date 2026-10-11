#pragma once

#include <simd/simd.h>
#include <string>

// A camera preset: world transform in OpenGL convention (looks down -Z, +Y up), vertical FOV in degrees.
struct CameraInfo {
    std::string name;
    simd_float4x4 matrix = matrix_identity_float4x4;
    float fov = 40.0f;
    float nearClip = 1.0f;
    float farClip = 10000.0f;
};
