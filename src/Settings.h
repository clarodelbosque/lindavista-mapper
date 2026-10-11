#pragma once

#import <Foundation/Foundation.h>
#include <simd/simd.h>
#include <string>
#include <vector>

// A node in the JSON settings tree. Child nodes are created on demand, so the same calls
// work for loading (missing keys fall back to defaults) and saving.
class Settings {
public:
    Settings() : dict_([NSMutableDictionary dictionary]) {}
    explicit Settings(NSMutableDictionary* dict) : dict_(dict) {}

    static Settings loadFile(const std::string& path);
    bool saveFile(const std::string& path) const;

    Settings child(const char* key);
    std::vector<Settings> list(const char* key) const;
    Settings appendToList(const char* key);
    bool has(const char* key) const;

    bool getBool(const char* key, bool fallback) const;
    int getInt(const char* key, int fallback) const;
    float getFloat(const char* key, float fallback) const;
    std::string getString(const char* key, const std::string& fallback) const;
    simd_float4x4 getMatrix(const char* key, const simd_float4x4& fallback) const;
    // Returns {} if the key is missing or isn't an array (e.g. an older settings file that
    // stored a single string under a now-reused-as-array key), never throws.
    std::vector<std::string> getStringList(const char* key) const;

    void setBool(const char* key, bool value);
    void setInt(const char* key, int value);
    void setFloat(const char* key, float value);
    void setString(const char* key, const std::string& value);
    void setMatrix(const char* key, const simd_float4x4& value);
    void setStringList(const char* key, const std::vector<std::string>& values);

private:
    id value(const char* key) const;
    NSMutableDictionary* dict_;
};

// ~/Library/Application Support/Linda Vista Mapper, created if needed.
std::string applicationSupportDirectory();
