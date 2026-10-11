#pragma once

#import <Foundation/Foundation.h>

#include "AppContext.h"
#include "Settings.h"

#include <string>
#include <vector>

class BaseManager {
public:
    virtual ~BaseManager() = default;

    virtual void setup(AppContext& context) { ctx = &context; }
    virtual void update() {}
    virtual void loadSettings(Settings& settings) {}
    virtual void saveSettings(Settings& settings) {}
    virtual void drawImGui() {}
    // Overlays drawn on the 3D view (camera badge, video seek bar). The classic ImGui
    // sidebar draws them from drawImGui(); the web panel calls this directly instead.
    virtual void drawOverlays() {}
    virtual void dragEvent(const std::vector<std::string>& files) {}

    // Web panel bridge (WebPanel.h): write this section's state into the JSON pushed to the
    // panel, and handle a panel action. Return true when the action was handled.
    virtual void writePanelState(NSMutableDictionary* state) {}
    virtual bool handlePanelAction(NSString* type, NSDictionary* action) { return false; }

protected:
    AppContext* ctx = nullptr;
    bool isGuiOpened = true;
};
