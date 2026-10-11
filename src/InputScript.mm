#include "InputScript.h"

#import <Carbon/Carbon.h>
#import <WebKit/WebKit.h>

#include <fstream>
#include <sstream>

bool InputScript::load(const std::string& path) {
    std::ifstream file(path);
    if (!file) return false;
    std::string line;
    while (std::getline(file, line)) {
        std::istringstream in(line);
        Command c;
        if (!(in >> c.frame >> c.action)) continue;
        if (c.action == "move") in >> c.x >> c.y;
        else if (c.action == "down" || c.action == "drag" || c.action == "up") in >> c.arg >> c.x >> c.y;
        else if (c.action == "key" || c.action == "keydown" || c.action == "keyup") in >> c.arg;
        else if (c.action == "scroll") in >> c.x >> c.y >> c.delta;
        else if (c.action == "js") std::getline(in >> std::ws, c.arg);
        commands_.push_back(c);
    }
    return true;
}

static NSPoint windowPoint(NSView* view, double x, double y) {
    return [view convertPoint:NSMakePoint(x, view.bounds.size.height - y) toView:nil];
}

static NSEvent* mouse(NSEventType type, NSWindow* window, NSView* view, double x, double y) {
    return [NSEvent mouseEventWithType:type location:windowPoint(view, x, y) modifierFlags:0
                             timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                               context:nil eventNumber:0 clickCount:1 pressure:1.0f];
}

// ImGui's OSX backend (imgui_impl_osx.mm) maps key events to ImGuiKey via event.keyCode,
// not via characters -- so a script line that is meant to drive ImGui's own keyboard nav
// (Tab/Shift-Tab/Enter) needs the real virtual key code, not just the right character.
// VMApp's own shortcuts (keyOf() in VMApp.mm) read charactersIgnoringModifiers instead, so
// they are unaffected either way; this table just makes every script key correct for both.
static unsigned short keyCodeFor(const std::string& c) {
    if (c == "space") return kVK_Space;
    if (c == "left") return kVK_LeftArrow;
    if (c == "right") return kVK_RightArrow;
    if (c == "tab") return kVK_Tab;
    if (c == "enter" || c == "return") return kVK_Return;
    if (c.size() == 1) {
        switch (c[0]) {
            case 'a': return kVK_ANSI_A;
            case 'b': return kVK_ANSI_B;
            case 'c': return kVK_ANSI_C;
            case 'd': return kVK_ANSI_D;
            case 'e': return kVK_ANSI_E;
            case 'f': return kVK_ANSI_F;
            case 'g': return kVK_ANSI_G;
            case 'h': return kVK_ANSI_H;
            case 'q': return kVK_ANSI_Q;
            case 'r': return kVK_ANSI_R;
            case 's': return kVK_ANSI_S;
            case 't': return kVK_ANSI_T;
            case 'v': return kVK_ANSI_V;
            case 'w': return kVK_ANSI_W;
            case 'x': return kVK_ANSI_X;
            case 'y': return kVK_ANSI_Y;
            case 'z': return kVK_ANSI_Z;
        }
    }
    return kVK_ANSI_A;  // matches this script format's previous (always-0/"A") fallback
}

// Shift is reported to ImGui only through NSEventTypeFlagsChanged (see
// imgui_impl_osx.mm's handler), never read from a keyDown/keyUp event's own
// modifierFlags -- so "shift-X" needs its own synthetic Shift flagsChanged event
// around the X key event, not just a modifier bit set on that event.
static NSEvent* flagsChanged(NSWindow* window, bool shiftDown) {
    return [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint
                        modifierFlags:(shiftDown ? NSEventModifierFlagShift : 0)
                            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                              context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO
                              keyCode:kVK_Shift];
}

static NSEvent* key(NSEventType type, NSWindow* window, const std::string& c) {
    // "shift-X" (e.g. "shift-tab") sends X with the Shift modifier held.
    bool shift = c.rfind("shift-", 0) == 0;
    std::string base = shift ? c.substr(6) : c;

    NSString* chars = @(base.c_str());
    if (base == "space") chars = @" ";
    else if (base == "left") chars = [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey];
    else if (base == "right") chars = [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey];
    else if (base == "tab") chars = @"\t";
    else if (base == "enter" || base == "return") chars = [NSString stringWithFormat:@"%C", (unichar)0x0D];

    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:(shift ? NSEventModifierFlagShift : 0)
                           timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                             context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO
                             keyCode:keyCodeFor(base)];
}

static WKWebView* findWebView(NSView* root) {
    if ([root isKindOfClass:WKWebView.class]) return (WKWebView*)root;
    for (NSView* child in root.subviews) {
        if (WKWebView* found = findWebView(child)) return found;
    }
    return nil;
}

void InputScript::post(int frame, NSWindow* window, NSView* view) const {
    for (const Command& c : commands_) {
        if (c.frame != frame) continue;
        bool right = c.arg == "right";
        if (c.action == "move") {
            [NSApp sendEvent:mouse(NSEventTypeMouseMoved, window, view, c.x, c.y)];
        } else if (c.action == "down") {
            [NSApp sendEvent:mouse(right ? NSEventTypeRightMouseDown : NSEventTypeLeftMouseDown, window, view, c.x, c.y)];
        } else if (c.action == "drag") {
            [NSApp sendEvent:mouse(right ? NSEventTypeRightMouseDragged : NSEventTypeLeftMouseDragged, window, view, c.x, c.y)];
        } else if (c.action == "up") {
            [NSApp sendEvent:mouse(right ? NSEventTypeRightMouseUp : NSEventTypeLeftMouseUp, window, view, c.x, c.y)];
        } else if (c.action == "key" || c.action == "keydown") {
            // keyDown/keyUp reach ImGui via the first-responder KeyEventResponder, which
            // [window sendEvent:] alone drives (see keyCodeFor()'s comment) -- but that
            // responder has no flagsChanged: override, so a Shift flagsChanged event only
            // reaches ImGui's HandleEvent through the local monitor NSApp installs, which
            // means it must go through [NSApp sendEvent:], not [window sendEvent:].
            bool shift = c.arg.rfind("shift-", 0) == 0;
            if (shift) [NSApp sendEvent:flagsChanged(window, true)];
            [window sendEvent:key(NSEventTypeKeyDown, window, c.arg)];
            if (c.action == "key") {
                [window sendEvent:key(NSEventTypeKeyUp, window, c.arg)];
                if (shift) [NSApp sendEvent:flagsChanged(window, false)];
            }
            // "keydown shift-X" leaves Shift physically "held" until a matching
            // "keyup shift-X" releases it below, same as holding a real key would.
        } else if (c.action == "keyup") {
            bool shift = c.arg.rfind("shift-", 0) == 0;
            [window sendEvent:key(NSEventTypeKeyUp, window, c.arg)];
            if (shift) [NSApp sendEvent:flagsChanged(window, false)];
        } else if (c.action == "js") {
            [findWebView(window.contentView) evaluateJavaScript:@(c.arg.c_str()) completionHandler:nil];
        } else if (c.action == "scroll") {
            NSPoint screen = [window convertPointToScreen:windowPoint(view, c.x, c.y)];
            CGFloat screenHeight = NSScreen.screens.firstObject.frame.size.height;
            CGEventRef cg = CGEventCreateScrollWheelEvent(nullptr, kCGScrollEventUnitPixel, 1, (int32_t)c.delta);
            CGEventSetLocation(cg, CGPointMake(screen.x, screenHeight - screen.y));
            CGEventSetIntegerValueField(cg, kCGMouseEventWindowUnderMousePointer, window.windowNumber);
            CGEventSetIntegerValueField(cg, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent, window.windowNumber);
            [NSApp sendEvent:[NSEvent eventWithCGEvent:cg]];
            CFRelease(cg);
        }
    }
}
