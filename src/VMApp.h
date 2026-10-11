#pragma once

#import <MetalKit/MetalKit.h>

#include "AppContext.h"
#include "MiscManager.h"
#include "Renderer.h"
#include "SceneManager.h"
#include "SourceManager.h"
#include "ViewManager.h"
#include "WebPanel.h"

#include <memory>

struct AppOptions {
    std::string settingsPath;  // defaults to ~/Library/Application Support/Linda Vista Mapper/settings.json
    std::string snapshotPath;  // when set: render, write a PNG of the window contents, quit
    int snapshotFrames = 90;
    std::string inputScriptPath;  // snapshot tests: synthetic input, see InputScript.h
    bool webUI = true;            // web panel (WebPanel.h); --classic-ui falls back to the ImGui sidebar
    std::string uiDevURL;         // web panel from a dev server (cd ui && npm run dev)
};

class VMApp {
public:
    bool setup(NSWindow* window, MTKView* view, const AppOptions& options, std::string& error);
    void frame(MTKView* view);
    void shutdown();

    void mouseDown(ViewManager::Button button, NSEvent* event);
    void mouseDragged(NSEvent* event);
    void mouseUp(NSEvent* event);
    void scrollWheel(NSEvent* event);
    void keyDown(NSEvent* event);
    void keyUp(NSEvent* event);
    void resetHeldKeys() {
        spaceDown_ = handDown_ = false;
        wDown_ = aDown_ = sDown_ = dDown_ = qDown_ = eDown_ = false;
    }
    void openFiles(const std::vector<std::string>& paths);
    void fullscreenChanged(bool fullscreen) { miscManager_.fullscreenChanged(fullscreen); }

private:
    void drawImGui();
    std::string settingsPath() const;
    simd_float2 viewPoint(NSEvent* event) const;
    void encodeSnapshot(id<MTLCommandBuffer> commandBuffer, id<MTLTexture> texture);
    void writeSnapshot(CGImageRef stage, int attempt);
    NSDictionary* panelState();
    void handlePanelAction(NSDictionary* action);
    void panelKey(NSDictionary* action);

    AppOptions options_;
    AppContext ctx_;
    MTKView* view_ = nil;
    id<MTLCommandQueue> queue_ = nil;
    Renderer renderer_;
    SceneManager sceneManager_;
    ViewManager viewManager_;
    SourceManager sourceManager_;
    MiscManager miscManager_;
    std::vector<BaseManager*> managers_;
    std::unique_ptr<WebPanel> webPanel_;
    std::string iniPath_;
    bool showControl_ = true;
    // Web panel layout, kept in settings even in classic-UI runs so it survives them.
    float panelWidth_ = WebPanel::kDefaultWidth;
    bool panelCollapsed_ = false;

    bool cameraDragging_ = false;
    bool spaceDown_ = false;
    bool spaceUsedForPan_ = false;
    bool handDown_ = false;
    // Walk-mode movement keys. Continuous, like spaceDown_/handDown_: set on keyDown
    // (including auto-repeat -- unlike single-shot shortcuts), cleared on keyUp and on
    // resetHeldKeys() (windowDidResignKey).
    bool wDown_ = false;
    bool aDown_ = false;
    bool sDown_ = false;
    bool dDown_ = false;
    bool qDown_ = false;
    bool eDown_ = false;
    int frameCount_ = 0;
};
