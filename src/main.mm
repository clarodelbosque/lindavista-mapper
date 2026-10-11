#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>

#include "InputScript.h"
#include "VMApp.h"

#include <algorithm>
#include <cstdlib>
#include <memory>

@interface VMView : MTKView
@property (nonatomic, assign) VMApp* app;
@end

@implementation VMView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)mouseDown:(NSEvent*)e { _app->mouseDown(ViewManager::Left, e); }
- (void)mouseDragged:(NSEvent*)e { _app->mouseDragged(e); }
- (void)mouseUp:(NSEvent*)e { _app->mouseUp(e); }
- (void)rightMouseDown:(NSEvent*)e { _app->mouseDown(ViewManager::Right, e); }
- (void)rightMouseDragged:(NSEvent*)e { _app->mouseDragged(e); }
- (void)rightMouseUp:(NSEvent*)e { _app->mouseUp(e); }
- (void)otherMouseDown:(NSEvent*)e {
    if (e.buttonNumber == 2) _app->mouseDown(ViewManager::Middle, e);
}
- (void)otherMouseDragged:(NSEvent*)e { _app->mouseDragged(e); }
- (void)otherMouseUp:(NSEvent*)e { _app->mouseUp(e); }
- (void)scrollWheel:(NSEvent*)e { _app->scrollWheel(e); }
- (void)keyDown:(NSEvent*)e { _app->keyDown(e); }
- (void)keyUp:(NSEvent*)e { _app->keyUp(e); }

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender { return NSDragOperationCopy; }

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL*>* urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
                                                                     options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    std::vector<std::string> paths;
    for (NSURL* url in urls) paths.push_back(url.path.UTF8String);
    _app->openFiles(paths);
    return YES;
}
@end

@interface VMAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, MTKViewDelegate>
- (instancetype)initWithOptions:(const AppOptions&)options;
@end

@implementation VMAppDelegate {
    AppOptions _options;
    VMApp _app;
    NSWindow* _window;
    VMView* _view;
}

- (instancetype)initWithOptions:(const AppOptions&)options {
    if ((self = [super init])) _options = options;
    return self;
}

static NSMenuItem* addItem(NSMenu* menu, NSString* title, SEL action, NSString* key, NSEventModifierFlags modifiers) {
    NSMenuItem* item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    item.keyEquivalentModifierMask = modifiers;
    return item;
}

- (void)buildMenu {
    NSMenu* bar = [NSMenu new];
    NSMenu* appMenu = [NSMenu new];
    addItem(appMenu, @"About Linda Vista Mapper", @selector(orderFrontStandardAboutPanel:), @"", 0);
    [appMenu addItem:[NSMenuItem separatorItem]];
    addItem(appMenu, @"Hide Linda Vista Mapper", @selector(hide:), @"h", NSEventModifierFlagCommand);
    addItem(appMenu, @"Hide Others", @selector(hideOtherApplications:), @"h",
            NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(appMenu, @"Show All", @selector(unhideAllApplications:), @"", 0);
    [appMenu addItem:[NSMenuItem separatorItem]];
    addItem(appMenu, @"Quit Linda Vista Mapper", @selector(terminate:), @"q", NSEventModifierFlagCommand);
    [bar addItemWithTitle:@"" action:nil keyEquivalent:@""].submenu = appMenu;

    NSMenu* windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    addItem(windowMenu, @"Minimize", @selector(performMiniaturize:), @"m", NSEventModifierFlagCommand);
    addItem(windowMenu, @"Zoom", @selector(performZoom:), @"", 0);
    addItem(windowMenu, @"Toggle Full Screen", @selector(toggleFullScreen:), @"f",
            NSEventModifierFlagCommand | NSEventModifierFlagControl);
    [bar addItemWithTitle:@"Window" action:nil keyEquivalent:@""].submenu = windowMenu;

    NSApp.mainMenu = bar;
    NSApp.windowsMenu = windowMenu;
}

- (void)fail:(NSString*)message {
    NSAlert* alert = [NSAlert new];
    alert.messageText = @"Linda Vista Mapper could not start";
    alert.informativeText = message;
    [alert runModal];
    [NSApp terminate:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    [self buildMenu];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return [self fail:@"This Mac does not support Metal."];

    NSRect frame = NSMakeRect(0, 0, 1024, 768);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = @"Linda Vista Mapper";
    _window.titlebarAppearsTransparent = YES;
    _window.titleVisibility = NSWindowTitleHidden;
    _window.backgroundColor = NSColor.blackColor;
    _window.acceptsMouseMovedEvents = YES;
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    [_window center];

    _view = [[VMView alloc] initWithFrame:frame device:device];
    _view.app = &_app;
    _view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _view.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    _view.sampleCount = 4;
    _view.clearColor = MTLClearColorMake(0, 0, 0, 1);
    _view.clearDepth = 0.0;
    _view.preferredFramesPerSecond = 60;
    _view.framebufferOnly = _options.snapshotPath.empty();
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    _view.colorspace = srgb;
    CGColorSpaceRelease(srgb);
    [_view registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    _window.contentView = _view;
    [_window makeKeyAndOrderFront:nil];

    std::string error;
    if (!_app.setup(_window, _view, _options, error)) return [self fail:@(error.c_str())];
    _view.delegate = self;

    if (!_options.snapshotPath.empty()) {
        // Snapshots must not depend on window stacking: MTKView stops drawing while occluded,
        // and macOS may decline to activate an app launched from a terminal.
        _window.level = NSFloatingWindowLevel;
        [_window orderFrontRegardless];
        _view.paused = YES;
        _view.enableSetNeedsDisplay = NO;
        VMView* view = _view;
        NSWindow* window = _window;
        auto script = std::make_shared<InputScript>();
        if (!_options.inputScriptPath.empty() && !script->load(_options.inputScriptPath)) {
            return [self fail:@"Could not read the input script."];
        }
        __block int frame = 0;
        [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer*) {
            script->post(++frame, window, view);
            [view draw];
        }];
    }

    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    } else {
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)drawInMTKView:(MTKView*)view { _app.frame(view); }
- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender { return YES; }
- (void)applicationWillTerminate:(NSNotification*)notification { _app.shutdown(); }

- (void)windowDidEnterFullScreen:(NSNotification*)notification { _app.fullscreenChanged(true); }
- (void)windowDidExitFullScreen:(NSNotification*)notification { _app.fullscreenChanged(false); }
- (void)windowDidResignKey:(NSNotification*)notification { _app.resetHeldKeys(); }
@end

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        AppOptions options;
        for (int i = 1; i < argc; ++i) {
            std::string arg = argv[i];
            bool hasValue = i + 1 < argc;
            if (arg == "--settings" && hasValue) options.settingsPath = argv[++i];
            else if (arg == "--snapshot" && hasValue) options.snapshotPath = argv[++i];
            else if (arg == "--snapshot-frames" && hasValue) options.snapshotFrames = std::max(1, atoi(argv[++i]));
            else if (arg == "--input-script" && hasValue) options.inputScriptPath = argv[++i];
            else if (arg == "--web-ui") options.webUI = true;  // now the default; kept for scripts that pass it explicitly
            else if (arg == "--classic-ui") options.webUI = false;
            else if (arg == "--ui-dev-url" && hasValue) options.uiDevURL = argv[++i];
        }

        if (!options.uiDevURL.empty()) options.webUI = true;

        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        VMAppDelegate* delegate = [[VMAppDelegate alloc] initWithOptions:options];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
