#pragma once

#include "BaseManager.h"
#include "SceneLoader.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <vector>

// Loads one or more FBX files additively: each adds its classified meshes to the scene
// (screens/stages/guides are simply unioned across files) and, if it has cameras, can
// import them into the global camera preset list.
//
// Add FBX and Reload parse the file on a background queue (the actual ufbx parse never
// touches entries_, the renderer or ImGui state directly) and hand the finished SceneData
// back to the main thread via ctx->runLater before anything shared is touched. While a
// load is in flight, its row shows "Loading..." and its own Reload/Remove are disabled;
// starting a new load via the "Add FBX" button or a file drop is blocked globally whenever
// any load is in flight (see anyLoadInFlight()), so at most one entry can be
// appended/replaced at a time.
class SceneManager : public BaseManager {
public:
    // entryId identifies which loaded file the cameras came from (stable across Reload,
    // never reused even after the entry is removed), so ViewManager can tag imported
    // presets with their true origin instead of matching by value.
    std::function<void(uint64_t entryId, const std::vector<CameraInfo>&)> onCameraListImport;
    // Called when an entry is removed, so the preset list (owned by ViewManager) can drop
    // any presets that came from it.
    std::function<void(uint64_t entryId)> onCameraListRemove;

    void drawImGui() override;
    void loadSettings(Settings& settings) override;
    void saveSettings(Settings& settings) override;
    void dragEvent(const std::vector<std::string>& files) override;
    void writePanelState(NSMutableDictionary* state) override;
    bool handlePanelAction(NSString* type, NSDictionary* action) override;

private:
    struct Entry {
        std::string path;
        std::unique_ptr<SceneData> scene;
        uint64_t fileSize = 0;
        uint64_t id = 0;
        // True from the moment a background load (Add or Reload) starts for this entry
        // until it finishes, successfully or not. The row shows "Loading..." in place of
        // its path/size text, and its Reload/Remove buttons are disabled, while this is
        // true.
        bool isLoading = false;
        // True after a first click on this row's "Remove" button turns it into "Confirm
        // Remove?", until a second click (which removes the entry) or until some other
        // action clears it again. Always false while isLoading (Remove is disabled then).
        bool confirmingRemove = false;
    };

    // Loads `path` synchronously and appends it as a new entry. Used only by
    // loadSettings, at startup before the UI exists and before any loading feedback would
    // be visible anyway. On failure, shows the "Unknown File Format" alert and leaves the
    // current list untouched.
    bool addFBXSync(const std::string& path);
    // Starts an asynchronous load of `path`: appends a placeholder entry immediately
    // (shown as "Loading..." until the background parse finishes) and clears any pending
    // remove-confirmation on every row. On failure, shows the alert and removes the
    // placeholder, leaving the list exactly as it was before the call. Used by the
    // "Add FBX" button and file drops.
    void addFBX(const std::string& path);
    // Starts an asynchronous reload of an existing entry's file, in place, and clears any
    // pending remove-confirmation on every row. The entry's previous scene/metadata stay
    // visible and intact until the load finishes; on failure they are left exactly as they
    // were (the alert is still shown).
    void reloadEntry(size_t index);
    // Drops an entry's meshes from the scene and asks ViewManager to drop any camera
    // presets imported from it.
    void removeEntry(size_t index);
    // Same as removeEntry, but finds the entry by its stable id (used to discard a failed
    // Add's placeholder, whose index may no longer be known/valid by the time the
    // background load's result comes back).
    void removeEntryById(uint64_t id);
    Entry* findEntryById(uint64_t id);
    // Runs the actual ufbx parse for `path` on a background utility queue -- a
    // self-contained computation that only ever touches its own local SceneData, never
    // entries_/the renderer/ImGui -- then hands the result back to the main thread via
    // ctx->runLater, which calls onBackgroundLoadFinished.
    void startBackgroundLoad(const std::string& path, uint64_t id);
    // Main-thread completion handler for startBackgroundLoad.
    void onBackgroundLoadFinished(uint64_t id, bool ok, uint64_t fileSize, std::shared_ptr<SceneData> scene);
    // Re-uploads the renderer's scene as the union of all entries' geometry.
    void rebuildCombinedScene();
    // True while any entry has a background load in flight. Used to disable "Add FBX"
    // globally, so two loads can never both try to append/replace an entry at once.
    bool anyLoadInFlight() const;

    std::vector<Entry> entries_;
    SceneData combined_;
    bool showFailedModal_ = false;
    // Monotonic counter for Entry::id. Never reused, so a removed entry's id can never
    // collide with a later one, even if the files are byte-identical.
    uint64_t nextEntryId_ = 1;
};
