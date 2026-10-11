#include "ViewManager.h"

#include "ImGuiApp.h"
#include "SourceManager.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

namespace {
// Walking speed, in centimeters per second (the scene's unit -- see HANDOFF.md 5.5/12).
constexpr float kWalkSpeedCmPerSec = 600.0f;
// Limits for the FOV control and the screen-blending opacity control (the UI limits, not
// the renderer's: a preset imported from an FBX may carry a wider FOV and keeps it).
constexpr float kMinFovDegrees = 1.0f;
constexpr float kMaxFovDegrees = 140.0f;
constexpr float kMinBlendOpacity = 0.1f;

double nowSeconds() {
    using namespace std::chrono;
    return duration<double>(steady_clock::now().time_since_epoch()).count();
}
}  // namespace

void ViewManager::setup(AppContext& context) {
    BaseManager::setup(context);
    // Alphabetical, matching the std::map ordering the 2.x panel used.
    visibility_ = {
        {"cameras", "Cameras", true},   {"grid", "Grid", true},       {"guides", "Guides", true},
        {"screens", "Screens", true},   {"stages", "Stages", true},   {"wireframe", "Wireframe", false},
    };
    resetCamera();
}

bool& ViewManager::visible(const char* key) {
    for (Visibility& v : visibility_) {
        if (strcmp(v.key, key) == 0) return v.value;
    }
    static bool missing = false;
    return missing;
}

void ViewManager::resetCamera() { cam_.reset(sceneEmpty_); }

void ViewManager::setSceneEmpty(bool empty) {
    if (empty == sceneEmpty_) return;
    // Follow the scene only while the camera is still untouched at the previous default
    // (a saved, preset, or user-moved camera stays where it is), and keep the user's
    // Fix Up Direction choice, which a reset would otherwise turn back on.
    GrabCamera previous;
    previous.reset(sceneEmpty_);
    bool untouched = cameraIndex_ == 0 && cam_.matches(previous.transform(), previous.fov);
    sceneEmpty_ = empty;
    if (untouched) {
        bool fixUp = cam_.fixUpDirection;
        resetCamera();
        cam_.fixUpDirection = fixUp;
    }
}

void ViewManager::applyCurrentCameraInfo() {
    if (cameraIndex_ == 0) {
        resetCamera();
        return;
    }
    const CameraInfo& info = cameraList_[cameraIndex_ - 1].info;
    cam_.setTransform(info.matrix);
    cam_.fov = info.fov;
}

void ViewManager::importCameraList(uint64_t originId, const std::vector<CameraInfo>& cameras) {
    for (const CameraInfo& info : cameras) cameraList_.push_back({info, originId});
}

void ViewManager::removeCameraList(uint64_t originId) {
    // originId == 0 means "no file origin" (manually added, or restored from a previous
    // session's settings.json) and must never be matched here, even if a SceneManager
    // entry id somehow ended up as 0.
    if (originId == 0) return;
    for (size_t i = cameraList_.size(); i-- > 0;) {
        if (cameraList_[i].originId != originId) continue;
        int removedIndex1Based = (int)i + 1;
        if (cameraIndex_ == removedIndex1Based) cameraIndex_ = 0;
        else if (cameraIndex_ > removedIndex1Based) --cameraIndex_;
        cameraList_.erase(cameraList_.begin() + i);
    }
}

std::string ViewManager::cameraNames() const {
    std::string names = "(Custom)";
    names += '\0';
    for (size_t i = 0; i < cameraList_.size(); ++i) {
        names += std::to_string(i + 1) + ": " + cameraList_[i].info.name;
        names += '\0';
    }
    names += '\0';
    return names;
}

std::vector<CameraInfo> ViewManager::cameraInfos() const {
    std::vector<CameraInfo> infos;
    infos.reserve(cameraList_.size());
    for (const CameraPreset& preset : cameraList_) infos.push_back(preset.info);
    return infos;
}

void ViewManager::update() {
    double now = nowSeconds();
    float dt = lastUpdateTime_ < 0.0 ? 0.0f : std::clamp((float)(now - lastUpdateTime_), 0.0f, 0.25f);
    lastUpdateTime_ = now;

    if (navMode_ == NavMode::Walk) {
        simd_float3 move = simd_make_float3(0, 0, 0);
        if (moveKeys_.w) move += cam_.forward();
        if (moveKeys_.s) move -= cam_.forward();
        if (moveKeys_.d) move += cam_.right();
        if (moveKeys_.a) move -= cam_.right();
        if (moveKeys_.e) move += simd_make_float3(0, 1, 0);
        if (moveKeys_.q) move -= simd_make_float3(0, 1, 0);
        float lenSq = simd_length_squared(move);
        if (lenSq > 1e-9f) cam_.position += (move / sqrtf(lenSq)) * (kWalkSpeedCmPerSec * dt);
    }

    if (cameraIndex_ < 1 || cameraIndex_ > (int)cameraList_.size()) {
        cameraIndex_ = 0;
        return;
    }
    const CameraInfo& info = cameraList_[cameraIndex_ - 1].info;
    if (!cam_.matches(info.matrix, info.fov)) cameraIndex_ = 0;
}

void ViewManager::drawImGui() {
    ImGui::SetNextItemOpen(isGuiOpened);
    if ((isGuiOpened = ImGui::CollapsingHeader("View"))) {
        if (ImGui::TreeNode("Cameras")) {
            std::string names = cameraNames();
            if (ImGui::Combo("##Camera", &cameraIndex_, names.c_str()) && cameraIndex_ >= 1) applyCurrentCameraInfo();

            ImGui::BeginDisabled(cameraIndex_ != 0);
            if (ImGui::Button("Add Camera")) requestAddCamera();
            ImGui::EndDisabled();

            ImGui::SameLine();
            ImGui::BeginDisabled(cameraIndex_ == 0);
            if (ImGui::Button("Delete Camera")) deleteCurrentCamera();
            ImGui::EndDisabled();

            ImGui::Text("Coord");
            float pos[3] = {cam_.position.x, cam_.position.y, cam_.position.z};
            if (ImGui::DragFloat3("Pos", pos, 1.0f, 0.0f, 0.0f, "%.1f")) cam_.position = simd_make_float3(pos[0], pos[1], pos[2]);

            simd_float3 euler = cam_.eulerDegrees() + 0.0f;  // + 0 turns -0.0 into 0.0 for display
            float rot[3] = {euler.x, euler.y, euler.z};
            if (ImGui::DragFloat3("Rot", rot, 1.0f, 0.0f, 0.0f, "%.1f")) cam_.setEulerDegrees(simd_make_float3(rot[0], rot[1], rot[2]));

            ImGui::SliderFloat("Fov", &cam_.fov, kMinFovDegrees, kMaxFovDegrees);
            ImGui::Checkbox("Fix Up Direction", &cam_.fixUpDirection);
            ImGui::TreePop();
        }

        if (ImGui::TreeNode("Visibility")) {
            ImGui::Columns(2, "visibility_column", false);
            for (Visibility& v : visibility_) {
                ImGui::Checkbox(v.label, &v.value);
                ImGui::NextColumn();
            }
            ImGui::Columns(1);
            ImGui::TreePop();
        }

        ImGui::Separator();
        ImGui::Checkbox("Enable Screen Blending", &enableScreenBlending_);
        ImGui::Separator();
    }
    drawOverlays();
}

void ViewManager::drawOverlays() {
    if (cameraIndex_ != 0) {
        ImVec2 display = ImGui::GetIO().DisplaySize;
        ImGui::SetNextWindowPos(ImVec2(display.x - 10, 10), ImGuiCond_Always, ImVec2(1, 0));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 2);
        ImGui::Begin("##CameraName", nullptr, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoMove |
                                              ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoSavedSettings |
                                              ImGuiWindowFlags_NoFocusOnAppearing | ImGuiWindowFlags_NoInputs);
        ImGui::Text("%d: %s", cameraIndex_, cameraList_[cameraIndex_ - 1].info.name.c_str());
        ImGui::End();
        ImGui::PopStyleVar();
    }
}

void ViewManager::writePanelState(NSMutableDictionary* state) {
    NSMutableArray* presets = [NSMutableArray array];
    for (const CameraPreset& preset : cameraList_) [presets addObject:@(preset.info.name.c_str())];
    NSMutableDictionary* visibility = [NSMutableDictionary dictionary];
    for (const Visibility& v : visibility_) visibility[@(v.key)] = @(v.value);
    // Position/rotation are rounded to 0.1 (same as the DragFloat3 "%.1f" display) so
    // camera navigation doesn't push a new state -- and re-render the panel -- every frame.
    auto round1 = [](float v) { return std::round(v * 10.0f) / 10.0f; };
    simd_float3 position = cam_.position;
    simd_float3 pos = {round1(position.x), round1(position.y), round1(position.z)};
    simd_float3 rotation = cam_.eulerDegrees() + 0.0f;  // +0 turns -0.0 into 0.0
    simd_float3 euler = {round1(rotation.x), round1(rotation.y), round1(rotation.z)};
    state[@"camera"] = @{
        @"index": @(cameraIndex_),
        @"presets": presets,
        @"position": @[@(pos.x), @(pos.y), @(pos.z)],
        @"rotation": @[@(euler.x), @(euler.y), @(euler.z)],
        // Rounded so camera navigation doesn't push a new state every frame.
        @"fov": @(std::round(cam_.fov * 10.0f) / 10.0f),
        @"fixUpDirection": @(cam_.fixUpDirection),
    };
    state[@"navMode"] = navMode_ == NavMode::Walk ? @"walk" : @"orbit";
    state[@"visibility"] = visibility;
    state[@"screenBlending"] = @(enableScreenBlending_);
    state[@"screenBlendOpacity"] = @(std::round(screenBlendOpacity_ * 100.0f) / 100.0f);
}

bool ViewManager::handlePanelAction(NSString* type, NSDictionary* action) {
    if ([type isEqualToString:@"setVisibility"]) {
        NSString* key = action[@"key"];
        if ([key isKindOfClass:NSString.class]) visible(key.UTF8String) = [action[@"value"] boolValue];
        return true;
    }
    if ([type isEqualToString:@"selectCamera"]) {
        int index = [action[@"index"] intValue];
        if (index < 0 || index > (int)cameraList_.size()) return true;
        cameraIndex_ = index;
        // Like the combo: choosing "(Custom)" keeps the current view rather than resetting it.
        if (cameraIndex_ >= 1) applyCurrentCameraInfo();
        return true;
    }
    if ([type isEqualToString:@"setNavMode"]) {
        setNavMode([action[@"mode"] isEqual:@"walk"] ? NavMode::Walk : NavMode::Orbit);
        return true;
    }
    if ([type isEqualToString:@"setCameraPosition"]) {
        NSArray* v = action[@"value"];
        if (v.count == 3) cam_.position = simd_make_float3([v[0] floatValue], [v[1] floatValue], [v[2] floatValue]);
        return true;
    }
    if ([type isEqualToString:@"setCameraRotation"]) {
        NSArray* v = action[@"value"];
        if (v.count == 3) cam_.setEulerDegrees(simd_make_float3([v[0] floatValue], [v[1] floatValue], [v[2] floatValue]));
        return true;
    }
    if ([type isEqualToString:@"setCameraFov"]) {
        cam_.fov = std::clamp([action[@"value"] floatValue], kMinFovDegrees, kMaxFovDegrees);
        return true;
    }
    if ([type isEqualToString:@"setFixUpDirection"]) {
        cam_.fixUpDirection = [action[@"value"] boolValue];
        return true;
    }
    if ([type isEqualToString:@"setScreenBlending"]) {
        enableScreenBlending_ = [action[@"value"] boolValue];
        return true;
    }
    if ([type isEqualToString:@"setScreenBlendOpacity"]) {
        float value = [action[@"value"] floatValue];
        if (std::isfinite(value)) screenBlendOpacity_ = std::clamp(value, kMinBlendOpacity, 1.0f);
        return true;
    }
    if ([type isEqualToString:@"addCamera"]) {
        requestAddCamera();
        return true;
    }
    if ([type isEqualToString:@"deleteCamera"]) {
        deleteCurrentCamera();
        return true;
    }
    return false;
}

void ViewManager::requestAddCamera() {
    if (cameraIndex_ != 0) return;
    ctx->runLater([this] {
        std::string name = "Camera " + std::to_string(cameraList_.size() + 1);
        if (!Dialogs::promptText("Name the new camera preset", name)) return;
        CameraInfo info;
        info.name = name;
        info.matrix = cam_.transform();
        info.fov = cam_.fov;
        cameraList_.push_back({info, 0});
        cameraIndex_ = (int)cameraList_.size();
    });
}

void ViewManager::deleteCurrentCamera() {
    if (cameraIndex_ == 0) return;
    cameraList_.erase(cameraList_.begin() + (cameraIndex_ - 1));
    cameraIndex_ = 0;
}

void ViewManager::setViewport(simd_float2 sizePoints, float pixelsPerPoint) {
    viewSize_ = simd_max(sizePoints, simd_make_float2(1, 1));
    pixelsPerPoint_ = std::max(pixelsPerPoint, 1.0f);
}

ViewParams ViewManager::viewParams() const {
    ViewParams p;
    p.view = cam_.viewMatrix();
    p.projection = cam_.projectionMatrix(viewSize_.x / viewSize_.y);
    p.viewportPixels = viewSize_ * pixelsPerPoint_;
    p.pixelsPerPoint = pixelsPerPoint_;
    p.nearClip = cam_.nearClip;
    return p;
}

void ViewManager::draw(id<MTLRenderCommandEncoder> enc, SourceManager& sources) {
    Renderer& r = *ctx->renderer;
    r.begin(enc, viewParams());
    if (visible("stages")) r.drawStages(enc);
    if (visible("guides")) r.drawGuides(enc);
    if (visible("screens")) {
        bool flipV = false;
        id<MTLTexture> texture = sources.currentTexture(&flipV);
        r.drawScreens(enc, texture, flipV, enableScreenBlending_, screenBlendOpacity_);
    }
    if (visible("wireframe")) r.drawWireframe(enc);
    if (visible("grid")) r.drawGrid(enc);
    if (visible("cameras")) r.drawCameraGlyphs(enc, cameraInfos());
}

void ViewManager::drawCameraLabels(ImDrawList* drawList, ImFont* font, float fontSize) {
    if (visible("cameras")) {
        ImU32 color = IM_COL32(255, 255, 255, 192);
        for (const CameraPreset& preset : cameraList_) {
            const CameraInfo& info = preset.info;
            simd_float2 p;
            if (!cam_.project(info.matrix.columns[3].xyz, viewSize_, &p)) continue;
            drawList->AddText(font, fontSize, ImVec2(p.x + 15, p.y - fontSize), color, info.name.c_str());
        }
    }

    if (navMode_ == NavMode::Walk) {
        // The only other hint that Walk mode is active -- the Misc section's "Walk
        // Navigation" checkbox -- disappears entirely whenever the Control panel is
        // hidden (C key). This indicator
        // is drawn on the same always-on background draw list as the camera labels above
        // (called every frame from VMApp::frame regardless of showControl_), not through a
        // normal ImGui window/badge like ##CameraName, so it keeps showing even then.
        // Bottom-right, clear of the top-right camera-name badge and the bottom-center
        // video seek bar.
        const char* text = "WALK";
        ImU32 color = IM_COL32(255, 255, 255, 192);  // same white-at-~75%-alpha convention as the camera labels
        ImVec2 size = font->CalcTextSizeA(fontSize, FLT_MAX, 0.0f, text);
        ImVec2 pos(viewSize_.x - 10.0f - size.x, viewSize_.y - 10.0f - size.y);
        drawList->AddText(font, fontSize, pos, color, text);
    }
}

simd_float3 ViewManager::pickPivot(simd_float2 point) {
    simd_float3 origin, dir;
    cam_.rayThrough(point, viewSize_, &origin, &dir);

    std::optional<float> depth = ctx->renderer->pickDepth(viewParams(), point * pixelsPerPoint_, visible("stages"),
                                                          visible("guides"), visible("screens"));
    simd_float3 hit;
    if (depth) {
        hit = cam_.worldAtDepth(point, viewSize_, *depth);
    } else if (fabsf(dir.y) > 1e-4f && -origin.y / dir.y > 0.0f && -origin.y / dir.y < 1e5f) {
        hit = origin + dir * (-origin.y / dir.y);  // the floor grid
    } else {
        hit = origin + dir * lastPivotDistance_;
    }
    lastPivotDistance_ = std::clamp(simd_distance(origin, hit), 10.0f, 1e5f);
    return hit;
}

void ViewManager::mouseDown(Button button, simd_float2 point, bool panModifier) {
    pivot_ = pickPivot(point);
    lastPoint_ = point;
    switch (button) {
        case Left: drag_ = panModifier ? Drag::Pan : Drag::Orbit; break;
        // In Walk mode, right-drag looks around in place instead of dollying -- the pivot
        // picked above simply goes unused for that drag.
        case Right: drag_ = navMode_ == NavMode::Walk ? Drag::Look : Drag::Dolly; break;
        case Middle: drag_ = Drag::Pan; break;
    }
}

void ViewManager::mouseDragged(simd_float2 point) {
    simd_float2 delta = point - lastPoint_;
    lastPoint_ = point;
    switch (drag_) {
        case Drag::Orbit: cam_.orbit(pivot_, delta, viewSize_); break;
        case Drag::Dolly: cam_.dolly(pivot_, expf(delta.y * 0.005f)); break;
        case Drag::Pan: cam_.pan(pivot_, delta, viewSize_); break;
        case Drag::Look: cam_.look(delta, viewSize_); break;
        case Drag::None: break;
    }
}

void ViewManager::mouseUp() { drag_ = Drag::None; }

void ViewManager::scroll(simd_float2 point, float delta) {
    simd_float3 target = pickPivot(point);
    cam_.dolly(target, powf(0.99f, std::clamp(delta, -50.0f, 50.0f)));
}

bool ViewManager::keyDown(unichar key) {
    int preset = (int)key - '0';
    if (preset >= 1 && preset <= 9 && preset <= (int)cameraList_.size()) {
        cameraIndex_ = preset;
        applyCurrentCameraInfo();
        return true;
    }
    switch (key) {
        case 'r': resetCamera(); return true;
        case 'x':  // both nav modes -- the sole wireframe-toggle key (W no longer does this)
            visible("wireframe") = !visible("wireframe");
            return true;
        case 'g': visible("guides") = !visible("guides"); return true;
    }
    return false;
}

void ViewManager::setNavMode(NavMode mode) {
    if (navMode_ == mode) return;
    navMode_ = mode;
    // Leave no residual drag or movement state behind when switching modes, so Orbit's
    // documented behavior resumes immediately with no leftover velocity or rotation drift.
    drag_ = Drag::None;
    moveKeys_ = MoveKeys{};
}

void ViewManager::setMoveKeysHeld(bool w, bool a, bool s, bool d, bool q, bool e) {
    moveKeys_ = {w, a, s, d, q, e};
}

void ViewManager::loadSettings(Settings& settings) {
    Settings s = settings.child("view");
    isGuiOpened = s.getBool("isGuiOpened", isGuiOpened);

    Settings vis = s.child("visibility");
    for (Visibility& v : visibility_) v.value = vis.getBool(v.key, v.value);

    Settings camera = s.child("camera");
    cam_.fixUpDirection = camera.getBool("fixUpDirection", true);
    Settings current = camera.child("current");
    cam_.setTransform(current.getMatrix("matrix", cam_.transform()));
    cam_.fov = current.getFloat("fov", cam_.fov);

    cameraList_.clear();
    for (const Settings& item : camera.list("list")) {
        CameraInfo info;
        info.name = item.getString("name", info.name);
        info.matrix = item.getMatrix("matrix", info.matrix);
        info.fov = item.getFloat("fov", info.fov);
        // originId 0: presets restored from a previous session have no live SceneManager
        // entry to tie back to, so they are never auto-removed by this session's loads.
        cameraList_.push_back({info, 0});
    }
    cameraIndex_ = std::clamp(camera.getInt("index", 0), 0, (int)cameraList_.size());

    enableScreenBlending_ = s.getBool("enableScreenBlending", false);
    float opacity = s.getFloat("screenBlendOpacity", 1.0f);
    screenBlendOpacity_ = std::isfinite(opacity) ? std::clamp(opacity, kMinBlendOpacity, 1.0f) : 1.0f;
    // Walk is the default for fresh settings; a saved "orbit" or "walk" is kept as is.
    navMode_ = s.getString("navMode", "walk") == "orbit" ? NavMode::Orbit : NavMode::Walk;
}

void ViewManager::saveSettings(Settings& settings) {
    Settings s = settings.child("view");
    s.setBool("isGuiOpened", isGuiOpened);

    Settings vis = s.child("visibility");
    for (const Visibility& v : visibility_) vis.setBool(v.key, v.value);

    Settings camera = s.child("camera");
    camera.setInt("index", cameraIndex_);
    camera.setBool("fixUpDirection", cam_.fixUpDirection);
    Settings current = camera.child("current");
    current.setMatrix("matrix", cam_.transform());
    current.setFloat("fov", cam_.fov);
    for (const CameraPreset& preset : cameraList_) {
        const CameraInfo& info = preset.info;
        Settings item = camera.appendToList("list");
        item.setString("name", info.name);
        item.setMatrix("matrix", info.matrix);
        item.setFloat("fov", info.fov);
    }

    s.setBool("enableScreenBlending", enableScreenBlending_);
    s.setFloat("screenBlendOpacity", screenBlendOpacity_);
    s.setString("navMode", navMode_ == NavMode::Walk ? "walk" : "orbit");
}
