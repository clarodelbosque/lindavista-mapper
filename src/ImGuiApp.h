#pragma once

#include "imgui.h"

#include <string>
#include <vector>

namespace ImGui {

void ApplyCustomStyle();

void BeginTransparentWindow(const char* name);
void EndTransparentWindow();

void Alert(const char* title, const char* text, bool* show);

bool PlayToggle(const char* label, bool* playing, const ImVec2& size);
bool Seekbar(const char* label, int* v, int vMin, int vMax, const ImVec2& size);

} // namespace ImGui

namespace Dialogs {

// Native open panel. Returns an empty string if cancelled.
std::string chooseFile(const char* title, const std::vector<std::string>& extensions = {});

// Native prompt with a single text field. Returns false if cancelled.
bool promptText(const char* message, std::string& value);

} // namespace Dialogs
