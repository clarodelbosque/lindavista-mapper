#include "VMApp.h"

#include "ImGuiApp.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"

#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>

bool VMApp::setup(NSWindow* window, MTKView* view, const AppOptions& options, std::string& error) {
    options_ = options;
    view_ = view;
    queue_ = [view.device newCommandQueue];

    ctx_.device = view.device;
    ctx_.window = window;
    ctx_.view = view;
    ctx_.renderer = &renderer_;
    ctx_.dataPath = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"data"].UTF8String;
    ctx_.runLater = [](std::function<void()> work) { dispatch_async(dispatch_get_main_queue(), ^{ work(); }); };

    if (!renderer_.init(view.device, queue_, view.colorPixelFormat, view.depthStencilPixelFormat, view.sampleCount, error)) {
        return false;
    }

    // Before ImGui's OSX backend attaches to the view, so it sees the final view hierarchy.
    if (options_.webUI) {
        webPanel_ = std::make_unique<WebPanel>();
        if (!webPanel_->install(window, view, options_.uiDevURL, [this](NSDictionary* action) { handlePanelAction(action); },
                                error)) {
            return false;
        }
    }

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    // Without this, ImGui sets io.WantCaptureKeyboard true the instant any nav-enabled
    // window (e.g. the Control sidebar) has nav focus -- which is always, since nothing
    // ever gives it ImGuiWindowFlags_NoNavInputs -- even with no widget actually active.
    // That would swallow every VMApp key shortcut (WASD/QE walk, 1-9, R, G, F, C, Space)
    // whenever the sidebar is simply open. ActiveId (an actually-active/edited widget) or
    // an open modal still forces WantCaptureKeyboard true below, so typing in a field still
    // takes priority over shortcuts, same as before this flag was added.
    io.ConfigNavCaptureKeyboard = false;
    // With the web panel, AppKit owns the cursor (WebKit over the panel, the resize cursor
    // on its edge); ImGui would otherwise reset it to an arrow every frame.
    if (webPanel_) io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;
    if (options_.settingsPath.empty()) {
        iniPath_ = applicationSupportDirectory() + "/imgui.ini";
        io.IniFilename = iniPath_.c_str();
    } else {
        io.IniFilename = nullptr;
    }
    std::string font = ctx_.dataFile("Karla-Regular.ttf");
    if (!io.Fonts->AddFontFromFileTTF(font.c_str(), 14.0f)) {
        error = "Missing font: " + font;
        return false;
    }
    ImGui::ApplyCustomStyle();
    ImGui_ImplMetal_Init(view.device);
    ImGui_ImplOSX_Init(view);

    managers_ = {&sceneManager_, &viewManager_, &sourceManager_, &miscManager_};
    for (BaseManager* manager : managers_) manager->setup(ctx_);
    sceneManager_.onCameraListImport = [this](uint64_t entryId, const std::vector<CameraInfo>& cameras) {
        viewManager_.importCameraList(entryId, cameras);
    };
    sceneManager_.onCameraListRemove = [this](uint64_t entryId) {
        viewManager_.removeCameraList(entryId);
    };
    sceneManager_.onSceneEmptyChanged = [this](bool empty) { viewManager_.setSceneEmpty(empty); };
    miscManager_.isWalkModeActive = [this] { return viewManager_.navMode() == ViewManager::NavMode::Walk; };
    miscManager_.setWalkModeActive = [this](bool walk) {
        viewManager_.setNavMode(walk ? ViewManager::NavMode::Walk : ViewManager::NavMode::Orbit);
    };

    Settings settings = Settings::loadFile(settingsPath());
    showControl_ = settings.getBool("showControl", true);
    Settings panel = settings.child("panel");
    panelWidth_ = panel.getFloat("width", WebPanel::kDefaultWidth);
    panelCollapsed_ = panel.getBool("collapsed", false);
    if (webPanel_) {
        webPanel_->setWidth(panelWidth_);
        webPanel_->setCollapsed(panelCollapsed_);
    }
    for (BaseManager* manager : managers_) manager->loadSettings(settings);
    return true;
}

std::string VMApp::settingsPath() const {
    return options_.settingsPath.empty() ? applicationSupportDirectory() + "/settings.json" : options_.settingsPath;
}

void VMApp::shutdown() {
    // Snapshot runs never touch the user's own settings file.
    if (!options_.snapshotPath.empty() && options_.settingsPath.empty()) return;
    Settings settings;
    settings.setBool("showControl", showControl_);
    if (webPanel_) {
        panelWidth_ = webPanel_->width();
        panelCollapsed_ = webPanel_->isCollapsed();
    }
    Settings panel = settings.child("panel");
    panel.setFloat("width", panelWidth_);
    panel.setBool("collapsed", panelCollapsed_);
    for (BaseManager* manager : managers_) manager->saveSettings(settings);
    settings.saveFile(settingsPath());
}

void VMApp::frame(MTKView* view) {
    @autoreleasepool {
        CGSize size = view.bounds.size;
        viewManager_.setViewport(simd_make_float2(size.width, size.height), view.window.backingScaleFactor);
        viewManager_.setMoveKeysHeld(wDown_, aDown_, sDown_, dDown_, qDown_, eDown_);
        for (BaseManager* manager : managers_) manager->update();
        if (webPanel_) {
            webPanel_->setVisible(showControl_);
            webPanel_->pushState(panelState());
        }

        MTLRenderPassDescriptor* pass = view.currentRenderPassDescriptor;
        id<CAMetalDrawable> drawable = view.currentDrawable;
        if (!pass || !drawable) return;

        ImGui_ImplMetal_NewFrame(pass);
        ImGui_ImplOSX_NewFrame(view);
        ImGui::NewFrame();
        drawImGui();
        viewManager_.drawCameraLabels(ImGui::GetBackgroundDrawList(), ImGui::GetFont(), 12.0f);
        ImGui::Render();

        id<MTLCommandBuffer> commandBuffer = [queue_ commandBuffer];
        id<MTLRenderCommandEncoder> enc = [commandBuffer renderCommandEncoderWithDescriptor:pass];
        viewManager_.draw(enc, sourceManager_);
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, enc);
        [enc endEncoding];

        if (!options_.snapshotPath.empty() && ++frameCount_ == options_.snapshotFrames) {
            if (webPanel_) webPanel_->captureSnapshot();
            encodeSnapshot(commandBuffer, drawable.texture);
        }
        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
    }
}

void VMApp::drawImGui() {
    ImGuiIO& io = ImGui::GetIO();
    if (showControl_ && webPanel_) {
        // The web panel replaces the sidebar; only the overlays on the 3D view stay in ImGui.
        for (BaseManager* manager : managers_) manager->drawOverlays();
    } else if (showControl_) {
        ImGui::SetNextWindowPos(ImVec2(0, 0));
        ImGui::SetNextWindowSize(ImVec2(250, io.DisplaySize.y), ImGuiCond_FirstUseEver);
        ImGui::SetNextWindowSizeConstraints(ImVec2(250, io.DisplaySize.y),
                                            ImVec2(std::max(250.0f, io.DisplaySize.x), io.DisplaySize.y));
        ImGui::Begin("Control", nullptr, ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar);
        if (ImGui::Button("Hide Control")) showControl_ = false;
        for (BaseManager* manager : managers_) manager->drawImGui();
        ImGui::End();
    } else {
        ImGui::SetNextWindowPos(ImVec2(0, 0));
        ImGui::BeginTransparentWindow("Show Control");
        if (ImGui::Button("Show Control")) showControl_ = true;
        ImGui::EndTransparentWindow();
    }
}

simd_float2 VMApp::viewPoint(NSEvent* event) const {
    NSPoint p = [view_ convertPoint:event.locationInWindow fromView:nil];
    return simd_make_float2(p.x, view_.bounds.size.height - p.y);
}

void VMApp::mouseDown(ViewManager::Button button, NSEvent* event) {
    cameraDragging_ = !ImGui::GetIO().WantCaptureMouse;
    if (!cameraDragging_) return;
    bool pan = button == ViewManager::Left && (spaceDown_ || handDown_);
    if (pan && spaceDown_) spaceUsedForPan_ = true;
    viewManager_.mouseDown(button, viewPoint(event), pan);
}

void VMApp::mouseDragged(NSEvent* event) {
    if (cameraDragging_) viewManager_.mouseDragged(viewPoint(event));
}

void VMApp::mouseUp(NSEvent* event) {
    if (cameraDragging_) viewManager_.mouseUp();
    cameraDragging_ = false;
}

void VMApp::scrollWheel(NSEvent* event) {
    if (ImGui::GetIO().WantCaptureMouse) return;
    float delta = (float)event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.1f : 1.0f);
    if (delta != 0.0f) viewManager_.scroll(viewPoint(event), delta);
}

static unichar keyOf(NSEvent* event) {
    NSString* chars = event.charactersIgnoringModifiers.lowercaseString;
    return chars.length ? [chars characterAtIndex:0] : 0;
}

static bool hasCommandModifiers(NSEvent* event) {
    return event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption);
}

void VMApp::keyDown(NSEvent* event) {
    if (ImGui::GetIO().WantCaptureKeyboard || hasCommandModifiers(event)) return;
    unichar key = keyOf(event);
    if (key == NSLeftArrowFunctionKey) return sourceManager_.stepVideo(-1);
    if (key == NSRightArrowFunctionKey) return sourceManager_.stepVideo(1);

    // WASD/QE are continuous walk-mode movement, the same category as the video arrow
    // keys above: they must keep registering on every auto-repeat, not just the first
    // press, so this runs before the single-shot isARepeat gate below.
    switch (key) {
        case 'w': wDown_ = true; break;
        case 'a': aDown_ = true; break;
        case 's': sDown_ = true; break;
        case 'd': dDown_ = true; break;
        case 'q': qDown_ = true; break;
        case 'e': eDown_ = true; break;
    }

    if (event.isARepeat) return;
    switch (key) {
        case ' ':
            spaceDown_ = true;
            spaceUsedForPan_ = false;
            return;
        case 'h': handDown_ = true; return;
        case 'f': miscManager_.toggleFullscreen(); return;
    }
    viewManager_.keyDown(key);
}

void VMApp::keyUp(NSEvent* event) {
    unichar key = keyOf(event);
    bool typing = ImGui::GetIO().WantCaptureKeyboard || hasCommandModifiers(event);
    switch (key) {
        case 'w': wDown_ = false; break;
        case 'a': aDown_ = false; break;
        case 's': sDown_ = false; break;
        case 'd': dDown_ = false; break;
        case 'q': qDown_ = false; break;
        case 'e': eDown_ = false; break;
    }
    if (key == ' ') {
        // Space doubles as a pan modifier, so only a tap (no drag) toggles playback.
        if (spaceDown_ && !spaceUsedForPan_ && !typing) sourceManager_.toggleVideoPlayback();
        spaceDown_ = false;
    } else if (key == 'h') {
        handDown_ = false;
    } else if (key == 'c' && !typing) {
        showControl_ = !showControl_;
    }
}

NSDictionary* VMApp::panelState() {
    NSMutableDictionary* state = [NSMutableDictionary dictionary];
    state[@"version"] = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    state[@"panelVisible"] = @(showControl_);
    for (BaseManager* manager : managers_) manager->writePanelState(state);
    return state;
}

void VMApp::handlePanelAction(NSDictionary* action) {
    NSString* type = action[@"type"];
    if (![type isKindOfClass:NSString.class]) return;
    if ([type isEqualToString:@"key"]) return panelKey(action);
    if ([type isEqualToString:@"setPanelVisible"]) {
        showControl_ = [action[@"visible"] boolValue];
        return;
    }
    if ([type isEqualToString:@"setPanelCollapsed"]) {
        if (webPanel_) webPanel_->setCollapsed([action[@"collapsed"] boolValue]);
        return;
    }
    for (BaseManager* manager : managers_) {
        if (manager->handlePanelAction(type, action)) return;
    }
}

// A shortcut key pressed while the panel had focus (ui/src/keys.ts), replayed as the
// key event the 3D view would have received, so every shortcut keeps a single code path.
void VMApp::panelKey(NSDictionary* action) {
    NSString* name = action[@"key"];
    if (![name isKindOfClass:NSString.class] || name.length == 0) return;
    NSString* chars = name;
    if ([name isEqualToString:@"space"]) chars = @" ";
    else if ([name isEqualToString:@"left"]) chars = [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey];
    else if ([name isEqualToString:@"right"]) chars = [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey];
    else if (name.length != 1) return;
    bool down = [action[@"phase"] isEqual:@"down"];
    NSEvent* event = [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:NSProcessInfo.processInfo.systemUptime
                                  windowNumber:ctx_.window.windowNumber
                                       context:nil
                                    characters:chars
                   charactersIgnoringModifiers:chars
                                     isARepeat:[action[@"repeat"] boolValue]
                                       keyCode:0];
    if (down) keyDown(event);
    else keyUp(event);
}

void VMApp::openFiles(const std::vector<std::string>& paths) {
    for (BaseManager* manager : managers_) manager->dragEvent(paths);
}

void VMApp::encodeSnapshot(id<MTLCommandBuffer> commandBuffer, id<MTLTexture> texture) {
    NSUInteger width = texture.width, height = texture.height, bytesPerRow = width * 4;
    id<MTLBuffer> buffer = [texture.device newBufferWithLength:bytesPerRow * height options:MTLResourceStorageModeShared];
    id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake(width, height, 1) toBuffer:buffer destinationOffset:0
      destinationBytesPerRow:bytesPerRow destinationBytesPerImage:bytesPerRow * height];
    [blit endEncoding];

    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer>) {
        CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef bitmap = CGBitmapContextCreate(buffer.contents, width, height, 8, bytesPerRow, srgb,
                                                    kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        CGImageRef image = CGBitmapContextCreateImage(bitmap);
        CGContextRelease(bitmap);
        CGColorSpaceRelease(srgb);
        dispatch_async(dispatch_get_main_queue(), ^{
            writeSnapshot(image, 0);
            CGImageRelease(image);
        });
    }];
}

// Writes the snapshot PNG and quits. With the web panel shown, waits for its (async)
// WKWebView snapshot and composites both into one image of the whole window content.
void VMApp::writeSnapshot(CGImageRef stage, int attempt) {
    bool withPanel = webPanel_ && webPanel_->isVisible();
    if (withPanel && !webPanel_->snapshotImage() && attempt < 100) {
        CGImageRetain(stage);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            writeSnapshot(stage, attempt + 1);
            CGImageRelease(stage);
        });
        return;
    }

    CGImageRef image = CGImageRetain(stage);
    if (withPanel && webPanel_->snapshotImage()) {
        CGFloat scale = view_.window.backingScaleFactor;
        auto pixels = [scale](NSRect r) {
            return CGRectMake(r.origin.x * scale, r.origin.y * scale, r.size.width * scale, r.size.height * scale);
        };
        NSSize size = webPanel_->container().bounds.size;
        CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef bitmap = CGBitmapContextCreate(nullptr, (size_t)(size.width * scale), (size_t)(size.height * scale), 8, 0,
                                                    srgb, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
        CGImageRef panel = [webPanel_->snapshotImage() CGImageForProposedRect:nullptr context:nil hints:nil];
        CGContextDrawImage(bitmap, pixels(webPanel_->panelFrame()), panel);
        CGContextDrawImage(bitmap, pixels(view_.frame), stage);
        CGImageRelease(image);
        image = CGBitmapContextCreateImage(bitmap);
        CGContextRelease(bitmap);
        CGColorSpaceRelease(srgb);
    }

    NSString* path = @(options_.snapshotPath.c_str());
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                                                                 (__bridge CFStringRef)UTTypePNG.identifier, 1, nullptr);
    CGImageDestinationAddImage(dest, image, nullptr);
    bool ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    CGImageRelease(image);
    fprintf(stderr, ok ? "snapshot written to %s\n" : "snapshot FAILED: %s\n", path.UTF8String);
    [NSApp terminate:nil];
}
