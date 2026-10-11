#include "MiscManager.h"

#include "ImGuiApp.h"

void MiscManager::applyWindowOnTop() {
    ctx->window.level = showWindowTop_ ? NSFloatingWindowLevel : NSNormalWindowLevel;
}

void MiscManager::toggleFullscreen() {
    [ctx->window toggleFullScreen:nil];
}

void MiscManager::drawImGui() {
    ImGui::SetNextItemOpen(isGuiOpened);
    if ((isGuiOpened = ImGui::CollapsingHeader("Misc"))) {
        if (ImGui::Checkbox("Show Window On Top", &showWindowTop_)) applyWindowOnTop();

        bool fullscreen = showFullscreen_;
        if (ImGui::Checkbox("Enable Fullscreen", &fullscreen)) toggleFullscreen();

        bool walk = isWalkModeActive && isWalkModeActive();
        if (ImGui::Checkbox("Walk Navigation", &walk)) {
            if (setWalkModeActive) setWalkModeActive(walk);
        }
        if (ImGui::IsItemHovered()) ImGui::SetTooltip("In Walk mode, WASD+QE fly the camera; right-drag looks around instead of dollying.");

        if (ImGui::Button("Help")) showHelp_ = true;
        if (showHelp_) drawHelp();

        ImGui::Separator();
    }
}

void MiscManager::drawHelp() {
    static const char* const help[][2] = {
        {"-- Orbit navigation (default) --", ""},
        {"Left click drag", "Rotate camera"},
        {"Right click drag", "Zoom camera"},
        {"Scroll", "Zoom camera"},
        {"Middle click drag", "Pan camera"},
        {"[H] / [Space] + Left click drag", "Pan camera"},
        {"[R]", "Reset camera"},
        {"[1-9]", "Switch cameras in the scene file"},
        {"", ""},
        {"-- Walk navigation (Misc section toggle) --", ""},
        {"Right click drag", "Look around (in place)"},
        {"[W] / [S]", "Move forward / back"},
        {"[A] / [D]", "Strafe left / right"},
        {"[Q] / [E]", "Move down / up"},
        {"", ""},
        {"[F]", "Toggle fullscreen"},
        {"[C]", "Toggle control panel"},
        {"[G]", "Toggle showing guides"},
        {"[X]", "Toggle showing wireframe"},
        {"", ""},
        {"[Space]", "Play / pause video"},
        {"[Left] / [Right]", "Step video frames"},
    };

    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 2);
    ImGui::Begin("Help", &showHelp_, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoSavedSettings);
    if (ImGui::BeginTable("help", 2, ImGuiTableFlags_BordersInnerV)) {
        for (const auto& row : help) {
            ImGui::TableNextRow();
            ImGui::TableNextColumn();
            ImGui::TextUnformatted(row[0]);
            ImGui::TableNextColumn();
            ImGui::TextUnformatted(row[1]);
        }
        ImGui::EndTable();
    }
    ImGui::End();
    ImGui::PopStyleVar();
}

void MiscManager::writePanelState(NSMutableDictionary* state) {
    state[@"misc"] = @{
        @"windowOnTop": @(showWindowTop_),
        @"fullscreen": @(showFullscreen_),
    };
}

bool MiscManager::handlePanelAction(NSString* type, NSDictionary* action) {
    if ([type isEqualToString:@"setWindowOnTop"]) {
        showWindowTop_ = [action[@"value"] boolValue];
        applyWindowOnTop();
        return true;
    }
    if ([type isEqualToString:@"toggleFullscreen"]) {
        toggleFullscreen();
        return true;
    }
    return false;
}

void MiscManager::loadSettings(Settings& settings) {
    Settings s = settings.child("misc");
    isGuiOpened = s.getBool("isGuiOpened", isGuiOpened);
    showWindowTop_ = s.getBool("showWindowTop", showWindowTop_);
    applyWindowOnTop();
}

void MiscManager::saveSettings(Settings& settings) {
    Settings s = settings.child("misc");
    s.setBool("isGuiOpened", isGuiOpened);
    s.setBool("showWindowTop", showWindowTop_);
}
