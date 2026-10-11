#pragma once

#include "BaseManager.h"

#include <functional>

class MiscManager : public BaseManager {
public:
    // Nav mode lives in ViewManager (it owns the camera); these let the low-visibility
    // Misc-section toggle read and change it without the managers holding pointers to
    // each other, the same wiring style as SceneManager's onCameraListImport/Remove.
    std::function<bool()> isWalkModeActive;
    std::function<void(bool)> setWalkModeActive;

    void drawImGui() override;
    void loadSettings(Settings& settings) override;
    void saveSettings(Settings& settings) override;
    void writePanelState(NSMutableDictionary* state) override;
    bool handlePanelAction(NSString* type, NSDictionary* action) override;

    void toggleFullscreen();
    void fullscreenChanged(bool isFullscreen) { showFullscreen_ = isFullscreen; }

private:
    void applyWindowOnTop();
    void drawHelp();

    bool showWindowTop_ = false;
    bool showFullscreen_ = false;
    bool showHelp_ = false;
};
