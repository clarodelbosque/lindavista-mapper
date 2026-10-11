#include "ImGuiApp.h"
#include "imgui_internal.h"

#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>

namespace ImGui {

// The Virtual Mapper 2.x palette, mapped onto the current Dear ImGui color slots.
void ApplyCustomStyle() {
    StyleColorsDark();
    ImGuiStyle& style = GetStyle();

    style.WindowRounding = 0;
    style.ScrollbarSize = 3;
    style.ScrollbarRounding = 0;
    style.FramePadding = ImVec2(6, 4);
    style.ItemSpacing = ImVec2(4, 8);
    style.FrameRounding = 2;
    style.GrabRounding = 2;
    style.WindowBorderSize = 0;
    style.PopupBorderSize = 0;
    style.DisabledAlpha = 0.25f;

    ImVec4* c = style.Colors;
    c[ImGuiCol_Text]                  = ImVec4(0.86f, 0.93f, 0.89f, 1.00f);
    c[ImGuiCol_TextDisabled]          = ImVec4(0.86f, 0.93f, 0.89f, 0.58f);
    c[ImGuiCol_WindowBg]              = ImVec4(0.13f, 0.14f, 0.17f, 0.70f);
    c[ImGuiCol_ChildBg]               = ImVec4(0.20f, 0.22f, 0.27f, 0.58f);
    c[ImGuiCol_PopupBg]               = ImVec4(0.13f, 0.14f, 0.17f, 0.92f);
    c[ImGuiCol_Border]                = ImVec4(0.13f, 0.14f, 0.17f, 0.00f);
    c[ImGuiCol_BorderShadow]          = ImVec4(0.13f, 0.14f, 0.17f, 0.00f);
    c[ImGuiCol_FrameBg]               = ImVec4(0.17f, 0.19f, 0.23f, 0.55f);
    c[ImGuiCol_FrameBgHovered]        = ImVec4(0.00f, 0.63f, 0.75f, 0.78f);
    c[ImGuiCol_FrameBgActive]         = ImVec4(0.00f, 0.63f, 0.75f, 1.00f);
    c[ImGuiCol_TitleBg]               = ImVec4(0.20f, 0.22f, 0.27f, 1.00f);
    c[ImGuiCol_TitleBgCollapsed]      = ImVec4(0.20f, 0.22f, 0.27f, 0.75f);
    c[ImGuiCol_TitleBgActive]         = ImVec4(0.00f, 0.63f, 0.75f, 1.00f);
    c[ImGuiCol_MenuBarBg]             = ImVec4(0.20f, 0.22f, 0.27f, 0.47f);
    c[ImGuiCol_ScrollbarBg]           = ImVec4(0.20f, 0.22f, 0.27f, 1.00f);
    c[ImGuiCol_ScrollbarGrab]         = ImVec4(0.47f, 0.77f, 0.83f, 0.21f);
    c[ImGuiCol_ScrollbarGrabHovered]  = ImVec4(0.00f, 0.63f, 0.75f, 0.78f);
    c[ImGuiCol_ScrollbarGrabActive]   = ImVec4(0.00f, 0.63f, 0.75f, 1.00f);
    c[ImGuiCol_CheckMark]             = ImVec4(0.00f, 0.63f, 0.75f, 0.80f);
    c[ImGuiCol_SliderGrab]            = ImVec4(0.47f, 0.77f, 0.83f, 0.14f);
    c[ImGuiCol_SliderGrabActive]      = ImVec4(0.00f, 0.63f, 0.75f, 1.00f);
    c[ImGuiCol_Button]                = ImVec4(0.47f, 0.77f, 0.83f, 0.14f);
    c[ImGuiCol_ButtonHovered]         = ImVec4(0.00f, 0.63f, 0.75f, 0.86f);
    c[ImGuiCol_ButtonActive]          = ImVec4(0.00f, 0.63f, 0.75f, 1.00f);
    c[ImGuiCol_Header]                = ImVec4(0.21f, 0.26f, 0.35f, 0.76f);
    c[ImGuiCol_HeaderHovered]         = ImVec4(0.00f, 0.63f, 0.75f, 0.86f);
    c[ImGuiCol_HeaderActive]          = ImVec4(0.00f, 0.63f, 0.75f, 1.00f);
    c[ImGuiCol_Separator]             = ImVec4(0.47f, 0.77f, 0.83f, 0.32f);
    c[ImGuiCol_SeparatorHovered]      = ImVec4(0.00f, 0.63f, 0.75f, 0.78f);
    c[ImGuiCol_SeparatorActive]       = ImVec4(0.00f, 0.63f, 0.75f, 1.00f);
    c[ImGuiCol_ResizeGrip]            = ImVec4(0.47f, 0.77f, 0.83f, 0.04f);
    c[ImGuiCol_ResizeGripHovered]     = ImVec4(0.00f, 0.63f, 0.75f, 0.78f);
    c[ImGuiCol_ResizeGripActive]      = ImVec4(0.00f, 0.63f, 0.75f, 1.00f);
    c[ImGuiCol_PlotLines]             = ImVec4(0.86f, 0.93f, 0.89f, 0.63f);
    c[ImGuiCol_PlotLinesHovered]      = ImVec4(0.00f, 0.63f, 0.75f, 1.00f);
    c[ImGuiCol_PlotHistogram]         = ImVec4(0.86f, 0.93f, 0.89f, 0.63f);
    c[ImGuiCol_PlotHistogramHovered]  = ImVec4(0.00f, 0.63f, 0.75f, 1.00f);
    c[ImGuiCol_TextSelectedBg]        = ImVec4(0.00f, 0.63f, 0.75f, 0.43f);
    c[ImGuiCol_ModalWindowDimBg]      = ImVec4(0.20f, 0.22f, 0.27f, 0.73f);
}

void BeginTransparentWindow(const char* name) {
    Begin(name, nullptr, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize |
                         ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_AlwaysAutoResize);
}

void EndTransparentWindow() { End(); }

void Alert(const char* title, const char* text, bool* show) {
    if (*show) {
        OpenPopup(title);
        *show = false;
    }
    PushStyleVar(ImGuiStyleVar_WindowRounding, 2);
    if (BeginPopupModal(title, nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
        Text("%s", text);
        Separator();
        if (Button("OK")) CloseCurrentPopup();
        EndPopup();
    }
    PopStyleVar();
}

bool PlayToggle(const char* label, bool* playing, const ImVec2& size) {
    ImVec2 itemSize = CalcItemSize(size, 0.0f, GetFrameHeight());
    ImVec2 pos = GetCursorScreenPos();
    float cx = pos.x + itemSize.x / 2, cy = pos.y + itemSize.y / 2;

    bool pressed = Button(label, itemSize);

    ImDrawList* drawList = GetWindowDrawList();
    ImU32 color = GetColorU32(ImGuiCol_Text);
    if (*playing) {
        drawList->AddRectFilled(ImVec2(cx - 6, cy - 7), ImVec2(cx - 2, cy + 7), color);
        drawList->AddRectFilled(ImVec2(cx + 2, cy - 7), ImVec2(cx + 6, cy + 7), color);
    } else {
        drawList->AddTriangleFilled(ImVec2(cx + 7, cy), ImVec2(cx - 4, cy + 7), ImVec2(cx - 4, cy - 7), color);
    }
    if (pressed) *playing = !*playing;
    return pressed;
}

bool Seekbar(const char* label, int* v, int vMin, int vMax, const ImVec2& size) {
    ImVec2 itemSize = CalcItemSize(size, CalcItemWidth(), GetFrameHeight());
    ImVec2 pos = GetCursorScreenPos();
    float cy = pos.y + itemSize.y / 2;

    ImVec4 text = GetStyleColorVec4(ImGuiCol_Text);
    ImU32 lineColor = ColorConvertFloat4ToU32(ImVec4(text.x * 0.8f, text.y * 0.8f, text.z * 0.8f, 0.5f));
    GetWindowDrawList()->AddLine(ImVec2(pos.x, cy), ImVec2(pos.x + itemSize.x, cy), lineColor);

    PushItemWidth(itemSize.x);
    PushStyleVar(ImGuiStyleVar_GrabMinSize, 18);
    PushStyleVar(ImGuiStyleVar_GrabRounding, 9);
    PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(GetStyle().FramePadding.x, (itemSize.y - GetFontSize()) * 0.5f));
    PushStyleColor(ImGuiCol_SliderGrab, ImVec4(text.x * 0.8f, text.y * 0.8f, text.z * 0.8f, 1.0f));
    PushStyleColor(ImGuiCol_FrameBg, ImVec4(0, 0, 0, 0));
    PushStyleColor(ImGuiCol_FrameBgHovered, ImVec4(0, 0, 0, 0));
    PushStyleColor(ImGuiCol_FrameBgActive, ImVec4(0, 0, 0, 0));
    bool changed = SliderInt(label, v, vMin, std::max(vMin, vMax), "");
    PopStyleColor(4);
    PopStyleVar(3);
    PopItemWidth();
    return changed;
}

} // namespace ImGui

namespace Dialogs {

std::string chooseFile(const char* title, const std::vector<std::string>& extensions) {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.message = @(title);
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    if (!extensions.empty()) {
        NSMutableArray<UTType*>* types = [NSMutableArray array];
        for (const std::string& ext : extensions) {
            UTType* type = [UTType typeWithFilenameExtension:@(ext.c_str())];
            if (type) [types addObject:type];
        }
        if (types.count) panel.allowedContentTypes = types;
    }
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return "";
    return panel.URL.path.UTF8String;
}

bool promptText(const char* message, std::string& value) {
    NSAlert* alert = [NSAlert new];
    alert.messageText = @(message);
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    field.stringValue = @(value.c_str());
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    if ([alert runModal] != NSAlertFirstButtonReturn) return false;
    value = field.stringValue.UTF8String;
    return true;
}

} // namespace Dialogs
