#pragma once

#import <Metal/Metal.h>

#include "BaseManager.h"
#include "Camera.h"
#include "CameraInfo.h"
#include "Renderer.h"

struct ImDrawList;
struct ImFont;
class SourceManager;

class ViewManager : public BaseManager {
public:
    enum Button { Left = 0, Right = 1, Middle = 2 };
    // Orbit (default): left-drag orbits, right-drag dollies, middle/H-drag pans -- all
    // around the picked pivot. Walk: WASD+QE fly the camera and right-drag looks around
    // in place. See HANDOFF.md section 7 for the full inventory.
    enum class NavMode { Orbit, Walk };

    void setup(AppContext& context) override;
    void update() override;
    void drawImGui() override;
    void drawOverlays() override;
    void writePanelState(NSMutableDictionary* state) override;
    bool handlePanelAction(NSString* type, NSDictionary* action) override;
    void loadSettings(Settings& settings) override;
    void saveSettings(Settings& settings) override;

    // `originId` identifies the SceneManager entry these cameras were imported from
    // (SceneManager::Entry::id), so a later removeCameraList(originId) can find exactly
    // these presets again regardless of any value edits made in between (see below).
    void importCameraList(uint64_t originId, const std::vector<CameraInfo>& cameras);
    // Drops any presets whose recorded origin is `originId` (tracked per-preset at import
    // time, not by matching value — a preset imported from a file keeps its origin even if
    // that file is later Reloaded with different camera values, or if another loaded file
    // happens to contain byte-identical camera data). If the active preset is one of them,
    // falls back to "(Custom)", same as the Delete Camera button. Presets added via "Add
    // Camera" have no file origin and are never matched by this.
    void removeCameraList(uint64_t originId);

    void setViewport(simd_float2 sizePoints, float pixelsPerPoint);
    ViewParams viewParams() const;
    void draw(id<MTLRenderCommandEncoder> enc, SourceManager& sources);
    void drawCameraLabels(ImDrawList* drawList, ImFont* font, float fontSize);

    void mouseDown(Button button, simd_float2 point, bool panModifier);
    void mouseDragged(simd_float2 point);
    void mouseUp();
    void scroll(simd_float2 point, float delta);
    bool keyDown(unichar key);

    NavMode navMode() const { return navMode_; }
    void setNavMode(NavMode mode);
    // Continuous WASD/QE held-state, set every frame from VMApp's key tracking (mirrors
    // spaceDown_/handDown_ there). Only applied while navMode() == Walk.
    void setMoveKeysHeld(bool w, bool a, bool s, bool d, bool q, bool e);

private:
    struct Visibility {
        const char* key;
        const char* label;
        bool value;
    };
    enum class Drag { None, Orbit, Dolly, Pan, Look };
    // A camera preset plus where it came from. originId == 0 means "no file origin" (added
    // via "Add Camera", or loaded from settings.json from a previous session), so it is
    // never auto-removed when a scene entry is removed.
    struct CameraPreset {
        CameraInfo info;
        uint64_t originId = 0;
    };

    bool& visible(const char* key);
    void applyCurrentCameraInfo();
    void resetCamera();
    void requestAddCamera();
    void deleteCurrentCamera();
    simd_float3 pickPivot(simd_float2 point);
    std::string cameraNames() const;
    std::vector<CameraInfo> cameraInfos() const;

    GrabCamera cam_;
    std::vector<CameraPreset> cameraList_;
    int cameraIndex_ = 0;  // 0 = custom, otherwise 1-based preset index
    std::vector<Visibility> visibility_;
    bool enableScreenBlending_ = false;

    simd_float2 viewSize_ = {1024, 768};
    float pixelsPerPoint_ = 1.0f;
    Drag drag_ = Drag::None;
    simd_float3 pivot_ = {0, 0, 0};
    simd_float2 lastPoint_ = {0, 0};
    float lastPivotDistance_ = 450.0f;

    NavMode navMode_ = NavMode::Orbit;
    struct MoveKeys {
        bool w = false, a = false, s = false, d = false, q = false, e = false;
    } moveKeys_;
    double lastUpdateTime_ = -1.0;  // seconds, steady_clock; negative means "no previous frame yet"
};
