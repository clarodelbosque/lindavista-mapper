#include "Settings.h"

#include <cmath>

static NSString* ns(const char* s) { return [NSString stringWithUTF8String:s] ?: @""; }

Settings Settings::loadFile(const std::string& path) {
    NSData* data = [NSData dataWithContentsOfFile:ns(path.c_str())];
    if (!data) return Settings();
    id root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if (![root isKindOfClass:[NSMutableDictionary class]]) return Settings();
    return Settings(root);
}

bool Settings::saveFile(const std::string& path) const {
    if (![NSJSONSerialization isValidJSONObject:dict_]) {
        NSLog(@"Linda Vista Mapper: settings contain values that cannot be written as JSON");
        return false;
    }
    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:dict_
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:&error];
    if (!data) {
        NSLog(@"Linda Vista Mapper: could not encode settings: %@", error);
        return false;
    }
    return [data writeToFile:ns(path.c_str()) options:NSDataWritingAtomic error:&error];
}

id Settings::value(const char* key) const { return dict_[ns(key)]; }

bool Settings::has(const char* key) const { return value(key) != nil; }

Settings Settings::child(const char* key) {
    id existing = value(key);
    if ([existing isKindOfClass:[NSMutableDictionary class]]) return Settings(existing);
    NSMutableDictionary* created = [NSMutableDictionary dictionary];
    dict_[ns(key)] = created;
    return Settings(created);
}

std::vector<Settings> Settings::list(const char* key) const {
    std::vector<Settings> out;
    id existing = value(key);
    if (![existing isKindOfClass:[NSArray class]]) return out;
    for (id item in (NSArray*)existing) {
        if ([item isKindOfClass:[NSMutableDictionary class]]) out.emplace_back(item);
    }
    return out;
}

Settings Settings::appendToList(const char* key) {
    NSMutableArray* array = value(key);
    if (![array isKindOfClass:[NSMutableArray class]]) {
        array = [NSMutableArray array];
        dict_[ns(key)] = array;
    }
    NSMutableDictionary* item = [NSMutableDictionary dictionary];
    [array addObject:item];
    return Settings(item);
}

bool Settings::getBool(const char* key, bool fallback) const {
    id v = value(key);
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : fallback;
}

int Settings::getInt(const char* key, int fallback) const {
    id v = value(key);
    return [v isKindOfClass:[NSNumber class]] ? [v intValue] : fallback;
}

float Settings::getFloat(const char* key, float fallback) const {
    id v = value(key);
    return [v isKindOfClass:[NSNumber class]] ? [v floatValue] : fallback;
}

std::string Settings::getString(const char* key, const std::string& fallback) const {
    id v = value(key);
    return [v isKindOfClass:[NSString class]] ? std::string([v UTF8String]) : fallback;
}

// Matrices are stored as 16 column-major floats (translation at indices 12-14),
// the same layout openFrameworks used for ofMatrix4x4::getPtr().
simd_float4x4 Settings::getMatrix(const char* key, const simd_float4x4& fallback) const {
    id v = value(key);
    if (![v isKindOfClass:[NSArray class]] || [v count] != 16) return fallback;
    simd_float4x4 m;
    for (int i = 0; i < 16; ++i) {
        id n = v[i];
        if (![n isKindOfClass:[NSNumber class]]) return fallback;
        m.columns[i / 4][i % 4] = [n floatValue];
    }
    return m;
}

std::vector<std::string> Settings::getStringList(const char* key) const {
    std::vector<std::string> out;
    id v = value(key);
    if (![v isKindOfClass:[NSArray class]]) return out;
    for (id item in (NSArray*)v) {
        if ([item isKindOfClass:[NSString class]]) out.emplace_back([item UTF8String]);
    }
    return out;
}

void Settings::setBool(const char* key, bool v) { dict_[ns(key)] = @(v); }
void Settings::setInt(const char* key, int v) { dict_[ns(key)] = @(v); }
// JSON cannot represent NaN or infinity.
static float finiteOrZero(float v) { return std::isfinite(v) ? v : 0.0f; }

void Settings::setFloat(const char* key, float v) { dict_[ns(key)] = @(finiteOrZero(v)); }
void Settings::setString(const char* key, const std::string& v) { dict_[ns(key)] = ns(v.c_str()); }

void Settings::setMatrix(const char* key, const simd_float4x4& m) {
    NSMutableArray* array = [NSMutableArray arrayWithCapacity:16];
    for (int i = 0; i < 16; ++i) [array addObject:@(finiteOrZero(m.columns[i / 4][i % 4]))];
    dict_[ns(key)] = array;
}

void Settings::setStringList(const char* key, const std::vector<std::string>& values) {
    NSMutableArray* array = [NSMutableArray arrayWithCapacity:values.size()];
    for (const std::string& v : values) [array addObject:ns(v.c_str())];
    dict_[ns(key)] = array;
}

std::string applicationSupportDirectory() {
    NSURL* base = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                         inDomain:NSUserDomainMask
                                                appropriateForURL:nil
                                                           create:YES
                                                            error:nil];
    NSURL* dir = [base URLByAppendingPathComponent:@"Linda Vista Mapper" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir.path.UTF8String;
}
