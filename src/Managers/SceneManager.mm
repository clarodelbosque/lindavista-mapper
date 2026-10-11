#include "SceneManager.h"

#include "ImGuiApp.h"
#include "Renderer.h"

#include <algorithm>
#include <cstdio>

namespace {

uint64_t fileSizeOnDisk(const std::string& path) {
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:@(path.c_str()) error:nil];
    id size = attrs[NSFileSize];
    return [size isKindOfClass:[NSNumber class]] ? (uint64_t)[size unsignedLongLongValue] : 0;
}

// e.g. 0 -> "0b", 2048 -> "2.0kb", 1258291 -> "1.2mb".
std::string humanFileSize(uint64_t bytes) {
    static const char* kUnits[] = {"b", "kb", "mb", "gb", "tb"};
    double size = (double)bytes;
    int unit = 0;
    while (size >= 1024.0 && unit < 4) {
        size /= 1024.0;
        ++unit;
    }
    char buf[32];
    if (unit == 0) std::snprintf(buf, sizeof(buf), "%llu%s", (unsigned long long)bytes, kUnits[unit]);
    else std::snprintf(buf, sizeof(buf), "%.1f%s", size, kUnits[unit]);
    return buf;
}

} // namespace

void SceneManager::writePanelState(NSMutableDictionary* state) {
    NSMutableArray* files = [NSMutableArray array];
    for (const Entry& entry : entries_) {
        NSString* path = @(entry.path.c_str());
        bool loaded = !entry.isLoading && entry.scene;
        [files addObject:@{
            @"id": @(entry.id),
            @"name": path.lastPathComponent,
            @"folder": path.stringByDeletingLastPathComponent.stringByAbbreviatingWithTildeInPath,
            @"size": [NSByteCountFormatter stringFromByteCount:(long long)entry.fileSize
                                                     countStyle:NSByteCountFormatterCountStyleFile],
            @"loading": @(entry.isLoading),
            @"cameras": @(loaded ? entry.scene->cameras.size() : 0),
            @"hasScreens": @(loaded && !entry.scene->screens.empty()),
        }];
    }
    state[@"scene"] = @{@"files": files};
}

bool SceneManager::handlePanelAction(NSString* type, NSDictionary* action) {
    if ([type isEqualToString:@"addSceneFile"]) {
        if (anyLoadInFlight()) return true;
        ctx->runLater([this] {
            std::string path = Dialogs::chooseFile("Load Scene File (.fbx)", {"fbx"});
            if (!path.empty()) addFBX(path);
        });
        return true;
    }
    if ([type isEqualToString:@"reloadSceneFile"]) {
        uint64_t id = [action[@"id"] unsignedLongLongValue];
        for (size_t i = 0; i < entries_.size(); ++i) {
            if (entries_[i].id == id) {
                reloadEntry(i);
                break;
            }
        }
        return true;
    }
    if ([type isEqualToString:@"removeSceneFile"]) {
        removeEntryById([action[@"id"] unsignedLongLongValue]);
        return true;
    }
    if ([type isEqualToString:@"importSceneCameras"]) {
        uint64_t id = [action[@"id"] unsignedLongLongValue];
        Entry* entry = findEntryById(id);
        if (entry && entry->scene && onCameraListImport) onCameraListImport(id, entry->scene->cameras);
        return true;
    }
    return false;
}

bool SceneManager::addFBXSync(const std::string& path) {
    auto scene = std::make_unique<SceneData>();
    std::string error;
    if (!loadScene(path, *scene, error)) {
        NSLog(@"Linda Vista Mapper: failed to load %s: %s", path.c_str(), error.c_str());
        showFailedModal_ = true;
        return false;
    }
    Entry entry;
    entry.path = path;
    entry.fileSize = fileSizeOnDisk(path);
    entry.scene = std::move(scene);
    entry.id = nextEntryId_++;
    entries_.push_back(std::move(entry));
    rebuildCombinedScene();
    return true;
}

void SceneManager::addFBX(const std::string& path) {
    for (Entry& e : entries_) e.confirmingRemove = false;

    Entry placeholder;
    placeholder.path = path;
    placeholder.id = nextEntryId_++;
    placeholder.isLoading = true;
    uint64_t id = placeholder.id;
    entries_.push_back(std::move(placeholder));

    startBackgroundLoad(path, id);
}

void SceneManager::reloadEntry(size_t index) {
    if (index >= entries_.size()) return;
    Entry& entry = entries_[index];
    if (entry.isLoading) return;
    for (Entry& e : entries_) e.confirmingRemove = false;
    entry.isLoading = true;
    startBackgroundLoad(entry.path, entry.id);
}

void SceneManager::startBackgroundLoad(const std::string& path, uint64_t id) {
    AppContext* ctxPtr = ctx;
    // Everything in `work` below runs on a background queue, off the main thread that
    // renders every frame and handles input. It only ever reads `path` from disk and
    // builds a fresh, local SceneData -- it never reaches into entries_, the renderer or
    // any ImGui state. `this` is captured only to be forwarded into the ctx->runLater
    // continuation below; it is never dereferenced on the background thread.
    std::function<void()> work = [ctxPtr, path, id, this] {
        auto scene = std::make_shared<SceneData>();
        std::string error;
        bool ok = loadScene(path, *scene, error);
        uint64_t size = ok ? fileSizeOnDisk(path) : 0;
        if (!ok) NSLog(@"Linda Vista Mapper: failed to load %s: %s", path.c_str(), error.c_str());

        // Hand the result back to the main thread; onBackgroundLoadFinished is the first
        // place any of SceneManager's shared state is touched.
        ctxPtr->runLater([this, id, ok, size, scene] {
            onBackgroundLoadFinished(id, ok, size, scene);
        });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ work(); });
}

void SceneManager::onBackgroundLoadFinished(uint64_t id, bool ok, uint64_t fileSize, std::shared_ptr<SceneData> scene) {
    Entry* entry = findEntryById(id);
    if (!entry) return;  // removed in the meantime -- shouldn't happen since Remove is disabled while isLoading.

    if (!ok) {
        showFailedModal_ = true;
        if (entry->scene) {
            // A Reload failed: leave this entry's previous geometry/metadata exactly as it
            // was before the attempt.
            entry->isLoading = false;
        } else {
            // A brand-new Add failed: drop the placeholder so the list ends up exactly as
            // it was before the call.
            removeEntryById(id);
        }
        return;
    }

    entry->scene = std::make_unique<SceneData>(std::move(*scene));
    entry->fileSize = fileSize;
    entry->isLoading = false;
    rebuildCombinedScene();
}

SceneManager::Entry* SceneManager::findEntryById(uint64_t id) {
    for (Entry& entry : entries_) {
        if (entry.id == id) return &entry;
    }
    return nullptr;
}

void SceneManager::removeEntryById(uint64_t id) {
    for (size_t i = 0; i < entries_.size(); ++i) {
        if (entries_[i].id == id) {
            removeEntry(i);
            return;
        }
    }
}

void SceneManager::removeEntry(size_t index) {
    if (index >= entries_.size()) return;
    const Entry& entry = entries_[index];
    // Always ask ViewManager to drop presets tagged with this entry's id, even if the
    // entry's *current* scene has no cameras (e.g. the source file was edited to remove
    // its cameras, then Reloaded, before Remove) — otherwise those presets would be
    // orphaned with no way to ever clean them up.
    if (onCameraListRemove) onCameraListRemove(entry.id);
    entries_.erase(entries_.begin() + index);
    rebuildCombinedScene();
}

void SceneManager::rebuildCombinedScene() {
    std::vector<const SceneData*> scenes;
    for (const Entry& entry : entries_) {
        if (entry.scene) scenes.push_back(entry.scene.get());
    }
    if (onSceneEmptyChanged) onSceneEmptyChanged(scenes.empty());
    if (scenes.empty()) {
        ctx->renderer->setScene(nullptr);
        return;
    }
    mergeScenesForRender(scenes, combined_);
    ctx->renderer->setScene(&combined_);
}

bool SceneManager::anyLoadInFlight() const {
    for (const Entry& entry : entries_) {
        if (entry.isLoading) return true;
    }
    return false;
}

void SceneManager::drawImGui() {
    ImGui::SetNextItemOpen(isGuiOpened);
    if ((isGuiOpened = ImGui::CollapsingHeader("Scene"))) {
        ImGui::BeginDisabled(anyLoadInFlight());
        if (ImGui::Button("Add FBX")) {
            ctx->runLater([this] {
                std::string path = Dialogs::chooseFile("Load Scene File (.fbx)", {"fbx"});
                if (!path.empty()) addFBX(path);
            });
        }
        ImGui::EndDisabled();

        if (entries_.empty()) {
            ImGui::TextUnformatted("(No Scene)");
        } else {
            float rowHeight = ImGui::GetTextLineHeightWithSpacing() * 4.0f;
            float visibleRows = std::min<float>((float)entries_.size(), 4.0f);
            // NavFlattened lets Tab/Shift-Tab reach the per-row Reload/Remove/Import Cameras
            // buttons below: without it, ImGui's keyboard nav treats this child as a separate
            // nav scope and Tab skips straight over its contents from the sidebar above.
            ImGui::BeginChild("##SceneFiles", ImVec2(0, rowHeight * visibleRows),
                              ImGuiChildFlags_Borders | ImGuiChildFlags_NavFlattened);
            size_t removeIndex = entries_.size();
            for (size_t i = 0; i < entries_.size(); ++i) {
                Entry& entry = entries_[i];
                ImGui::PushID((int)i);

                if (entry.isLoading) {
                    ImGui::TextUnformatted("Loading...");
                } else {
                    ImGui::TextUnformatted(entry.path.c_str());
                    ImGui::Text("%s", humanFileSize(entry.fileSize).c_str());
                    if (entry.scene && !entry.scene->cameras.empty()) {
                        if (ImGui::Button("Import Cameras") && onCameraListImport) onCameraListImport(entry.id, entry.scene->cameras);
                        ImGui::SameLine();
                        ImGui::Text("Number: %zu", entry.scene->cameras.size());
                    }
                }

                ImGui::BeginDisabled(entry.isLoading);
                if (ImGui::Button("Reload")) reloadEntry(i);
                // A little extra spacing keeps Remove/Confirm from sitting direct
                // mouse-neighbors of Reload.
                ImGui::SameLine(0.0f, ImGui::GetStyle().ItemSpacing.x * 3.0f);
                // "###Remove" keeps this button's ID stable across the label swap below
                // (ID hashing resets at "###", see ImHashStr): without it, confirming via
                // keyboard nav is impossible -- the label change from "Remove" to "Confirm
                // Remove?" would normally also change the widget's ID, so the nav cursor
                // that just activated "Remove" has nothing to find when Enter is pressed a
                // second time to confirm. Mouse clicks were never affected, since they hit
                // whatever is under the cursor fresh each frame rather than tracking an ID.
                if (ImGui::Button(entry.confirmingRemove ? "Confirm Remove?###Remove" : "Remove###Remove")) {
                    if (entry.confirmingRemove) {
                        removeIndex = i;
                    } else {
                        // First click: arm this row's confirmation and disarm every other
                        // row's, so at most one row is ever mid-confirm.
                        for (Entry& e : entries_) e.confirmingRemove = false;
                        entry.confirmingRemove = true;
                    }
                }
                ImGui::EndDisabled();

                ImGui::Separator();
                ImGui::PopID();
            }
            if (removeIndex < entries_.size()) removeEntry(removeIndex);
            ImGui::EndChild();
        }
        ImGui::Separator();
    }

    ImGui::Alert("Unknown File Format", "Failed to load FBX file.", &showFailedModal_);
}

void SceneManager::loadSettings(Settings& settings) {
    Settings s = settings.child("scene");
    isGuiOpened = s.getBool("isGuiOpened", isGuiOpened);
    // Old settings files stored a single "fbxPath" string; that key is no longer read, so
    // they simply resolve to no entries rather than crashing.
    for (const std::string& path : s.getStringList("fbxPaths")) addFBXSync(path);
}

void SceneManager::saveSettings(Settings& settings) {
    Settings s = settings.child("scene");
    s.setBool("isGuiOpened", isGuiOpened);
    std::vector<std::string> paths;
    for (const Entry& entry : entries_) paths.push_back(entry.path);
    s.setStringList("fbxPaths", paths);
}

void SceneManager::dragEvent(const std::vector<std::string>& files) {
    if (files.size() != 1) return;
    if (anyLoadInFlight()) return;  // Same invariant as the "Add FBX" button: at most one load at a time.
    NSString* ext = [@(files[0].c_str()) pathExtension].lowercaseString;
    if ([ext isEqualToString:@"fbx"]) addFBX(files[0]);
}
