#pragma once

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>

#include <functional>
#include <string>

class Renderer;

// Shared services handed to every manager and source.
struct AppContext {
    id<MTLDevice> device = nil;
    NSWindow* window = nil;
    NSView* view = nil;
    Renderer* renderer = nullptr;
    std::string dataPath;

    // Runs work after the current frame finishes (for modal dialogs and other blocking UI).
    std::function<void(std::function<void()>)> runLater;

    std::string dataFile(const char* name) const { return dataPath + "/" + name; }
};
