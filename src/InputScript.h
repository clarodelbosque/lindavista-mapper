#pragma once

#import <Cocoa/Cocoa.h>

#include <string>
#include <vector>

// Scripted input for snapshot tests. Each line: "<frame> <command> [args]", with view
// points measured from the top-left of the content view:
//   move X Y | down left|right X Y | drag left|right X Y | up left|right X Y
//   key C | keydown C | keyup C | scroll X Y DELTA | js CODE (rest of the line, run in the
//   web panel -- e.g. clicking a control by its data-testid)
// C is a single lowercase letter, or one of: space, left, right, tab, enter (return also
// accepted), each optionally prefixed "shift-" (e.g. "shift-tab") to hold Shift as well.
// These carry the real macOS virtual key code, not just the character, so they drive
// ImGui's own keyboard nav (Tab/Shift-Tab/Enter) correctly, not only VMApp's shortcuts.
class InputScript {
public:
    bool load(const std::string& path);
    void post(int frame, NSWindow* window, NSView* view) const;

private:
    struct Command {
        int frame = 0;
        std::string action, arg;
        double x = 0, y = 0, delta = 0;
    };
    std::vector<Command> commands_;
};
