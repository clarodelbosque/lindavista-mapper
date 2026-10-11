#pragma once

#import <Metal/Metal.h>

#include "AppContext.h"
#include "Settings.h"

#include <string>

class BaseSource {
public:
    virtual ~BaseSource() = default;

    virtual void setup(AppContext& context) { ctx = &context; }
    virtual const char* name() const = 0;
    virtual void loadSettings(Settings& settings) {}
    virtual void saveSettings(Settings& settings) {}
    virtual void onActivated() {}
    virtual void onDeactivated() {}
    virtual void update() {}
    virtual void drawImGui() {}
    // Overlays on the 3D view; leftInset is the width covered by a sidebar (0 when the
    // 3D view is already beside the panel).
    virtual void drawOverlays(float leftInset) {}

    // One-line status for the web panel. level: 0 = nothing loaded, 1 = waiting, 2 = ready.
    struct Status {
        std::string text;
        int level = 0;
    };
    virtual Status status() const { return {}; }

    // Current frame, or nil when the source has nothing to show.
    virtual id<MTLTexture> texture() = 0;

    // True when row 0 holds the bottom of the image (OpenGL/IOSurface convention, e.g. Syphon).
    virtual bool isBottomUp() const { return false; }

    virtual bool openPath(const std::string& path) { return false; }

protected:
    AppContext* ctx = nullptr;
};
