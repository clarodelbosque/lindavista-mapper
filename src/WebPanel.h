#pragma once

#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>

#include <functional>
#include <string>

@class WKWebView;
@class VMPanelContainer;

// Control panel built with web technology (React + shadcn/ui, sources in ui/). It is the
// default UI; --classic-ui selects the ImGui sidebar instead.
// A WKWebView is docked to the left of the window and the 3D view gets the rest, so the
// panel never covers the scene (the classic ImGui sidebar is an overlay). Its right edge
// can be dragged to resize it; dragging below the minimum width collapses it to an icon
// rail (the page switches layout by its own width, see ui/src/App.tsx).
//
// Bridge, both directions JSON:
//   panel -> app: window.webkit.messageHandlers.vm.postMessage({type, ...}) -> onAction
//   app -> panel: pushState(dict) -> window.__vmReceive(state), only when the state changed
class WebPanel {
public:
    static constexpr CGFloat kDefaultWidth = 280;
    static constexpr CGFloat kMinWidth = 280;
    static constexpr CGFloat kMaxWidth = 520;
    static constexpr CGFloat kRailWidth = 60;
    static constexpr CGFloat kMinStageWidth = 320;  // the 3D view never gets narrower than this

    // Replaces the window's content view with a container holding the panel and `view`.
    // `devURL` (optional) loads a dev server (npm run dev) instead of the bundled panel.
    bool install(NSWindow* window, MTKView* view, const std::string& devURL,
                 std::function<void(NSDictionary*)> onAction, std::string& error);

    void pushState(NSDictionary* state);
    void setVisible(bool visible);
    bool isVisible() const;
    void setCollapsed(bool collapsed);
    bool isCollapsed() const;
    // Expanded width in points (kept while collapsed), restored from settings at launch.
    void setWidth(float width);
    float width() const;

    // Snapshot support: capture the panel's pixels, then composite them with the 3D view.
    void captureSnapshot();
    NSImage* snapshotImage() const { return snapshot_; }
    NSView* container() const;
    NSRect panelFrame() const;

private:
    VMPanelContainer* container_ = nil;
    WKWebView* webView_ = nil;
    id handler_ = nil;
    id navigationDelegate_ = nil;
    NSString* lastState_ = nil;
    bool ready_ = false;
    NSImage* snapshot_ = nil;
};
