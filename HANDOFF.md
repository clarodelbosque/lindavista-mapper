# Linda Vista Mapper: Handoff

Linda Vista Mapper is a native Apple Silicon (arm64) rebuild of [Virtual Mapper](https://github.com/baku89/VirtualMapper) by Baku Hashimoto (MIT licensed; see `LICENSE`). This document is the handoff for whoever works on it next. It covers everything the app does, where each piece lives, and how to verify changes without a human clicking around.

- **Status:** working. Version 3.1.0. As of the last full run (Oct 1), `make`, `make test` and `make smoke` (24 checks) passed. Re-run them on a fresh checkout before relying on that; `make smoke` runs the **classic ImGui UI** only (see [8.4](#84-keep-the-tests-in-step-with-the-layout)).
- **Default UI:** a **web panel** (React + shadcn/ui in `ui/`, shown in a `WKWebView` docked to the left of the window; see [5.8](#58-web-panel-default-ui)). The original **classic ImGui sidebar** is still built in and selected with `--classic-ui` (`make run-classic`). [Section 6](#6-ui-inventory-current-design) inventories the classic sidebar (the 2.x behavior being matched); [6.5](#65-web-panel-controls) lists the web panel's controls.
- **Scope so far:** a behavior-faithful clone of Virtual Mapper 2.3.1 (same panels, controls and shortcuts), plus the fixes and additions listed in [Differences from 2.3.1](#9-differences-from-virtual-mapper-231) — notably composite (multi-file) FBX loading, an opt-in Walk navigation mode alongside the original Orbit controls, and the web panel.
- **Not yet verified:** real Cinema 4D scenes, and real Syphon senders (After Effects, Resolume, VDMX). See [Verification status](#10-verification-status).
- **Next steps:** the open items in [`UX-AUDIT.md`](UX-AUDIT.md) (many of its findings were written against the classic sidebar; re-check each against the web panel), plus the planned FPS readout and render effects in [section 14](#14-known-limitations-and-backlog).

---

## Contents

1. [Quick start](#1-quick-start)
2. [What Linda Vista Mapper does](#2-what-linda-vista-mapper-does)
3. [Why a rewrite, and what replaced what](#3-why-a-rewrite-and-what-replaced-what)
4. [Project layout](#4-project-layout)
5. [Architecture](#5-architecture)
6. [UI inventory (current design)](#6-ui-inventory-current-design)
7. [Controls inventory (mouse and keyboard)](#7-controls-inventory-mouse-and-keyboard)
8. [Notes for the redesign](#8-notes-for-the-redesign)
9. [Differences from Virtual Mapper 2.3.1](#9-differences-from-virtual-mapper-231)
10. [Verification status](#10-verification-status)
11. [Testing toolkit](#11-testing-toolkit)
12. [Settings schema](#12-settings-schema)
13. [Rendering details](#13-rendering-details)
14. [Known limitations and backlog](#14-known-limitations-and-backlog)
15. [Environment gotchas](#15-environment-gotchas)
16. [Dependencies and licenses](#16-dependencies-and-licenses)
17. [Upstream-to-rebuild file map](#17-upstream-to-rebuild-file-map)

---

## 1. Quick start

Requirements: an Apple Silicon Mac, macOS 12 or later, the **Xcode Command Line Tools**, and **Node.js with npm** (the web panel is built from `ui/` as part of every `make`). Full Xcode is not needed.

| Command | What it does |
|---|---|
| `make` | Builds the web panel (`npm install` the first time, then `npm run build` in `ui/`), then `build/Linda Vista Mapper.app` (about 10 s of native compilation from clean, zero warnings), ad-hoc signed. The panel is baked into the bundle as `Contents/Resources/ui/index.html`. |
| `make run` | Builds if needed, then opens the app (web panel UI). |
| `make run-classic` | Same, but with the classic ImGui sidebar (`--classic-ui`). |
| `make ui` | Builds only the web panel (`ui/dist/index.html`). |
| `make test` | Unit tests: FBX loading, camera math, and GPU picking (headless). |
| `make tools` | Builds the dev helpers: Syphon test sender and test-movie generator. |
| `make smoke` | End-to-end checks with the real app. Opens its window briefly several times; about 20 s. |
| `make clean` | Deletes `build/`. |
| `make ARCHS="arm64 x86_64"` | Optional universal build (untested on Intel). |

The app lives at `build/Linda Vista Mapper.app`; drag it to `/Applications` to install. It is ad-hoc signed and not notarized. On another Mac, right-click → **Open** the first time, or run `xattr -dr com.apple.quarantine "Linda Vista Mapper.app"`.

---

## 2. What Linda Vista Mapper does

A preview tool for projection mapping and non-flat screens. You load a stage model (FBX) and pick a video source. The source is textured onto the model's screen surfaces, so you can see the content in 3D while you create it in another app.

**Scene conventions** (unchanged from 2.x; prefix matching is case-sensitive):
- Meshes whose **node name starts with `screen`** display the current source (they need UVs).
- Meshes starting with **`guide`** are guides, which can be toggled with `G`.
- Everything else is **stage** geometry, lit by a headlight at the camera.
- **Cameras** in the FBX can be imported as presets. Perspective only; orthographic cameras are skipped.
- Materials: diffuse and "luminance" (emissive) colors are used, plus ambient and specular. No textures, animation or lights.
- Units: the scene is normalized to Y-up centimeters, like 2.x. The grid has 1 m cells.

**Sources:** **Syphon** (live frames from other apps), **Image** (any ImageIO format: PNG, JPEG, TIFF, PSD, HEIC, EXR…) and **Video** (anything AVFoundation plays: H.264, HEVC, ProRes…). Video loops, has a seek bar, and supports frame stepping.

---

## 3. Why a rewrite, and what replaced what

Virtual Mapper 2.3.1 was built on openFrameworks 0.9 and linked against prebuilt **Intel-only** binaries. It could not simply be recompiled for arm64, so it was rebuilt on modern native components. The C++ structure (managers and sources) mirrors the original.

| Concern | 2.3.1 | Rebuild |
|---|---|---|
| Framework | openFrameworks 0.9 (GLFW, OpenGL 2 fixed function) | AppKit + **MetalKit** (`MTKView`), Objective-C++ |
| Rendering | OpenGL (deprecated on macOS) | **Metal**, shaders compiled at runtime (no offline Metal compiler without Xcode) |
| FBX | Autodesk FBX SDK 2016.1 via ofxFBX (Intel-only static lib) | **ufbx 0.23.1** (open source, vendored) |
| Syphon | Syphon.framework (2019 SDK, pre-Apple Silicon) via ofxSyphon | **Syphon-Framework master, built from source** (Metal client) |
| UI | ofxImGui with an ImGui from about 2016 | A **web panel** (React + shadcn/ui in a `WKWebView`) by default, plus the **Dear ImGui 1.92.9** sidebar with the original custom style ported (`--classic-ui`) |
| Video | ofVideoPlayer (AVFoundation) | AVPlayer + AVPlayerItemVideoOutput → CVMetalTextureCache (zero-copy) |
| Images | FreeImage | ImageIO → sRGB RGBA8 texture |
| Settings | `settings.xml` inside the app bundle | JSON in `~/Library/Application Support/Linda Vista Mapper/` |
| Camera nav | ofxGrabCam | `GrabCamera` (own implementation) plus a GPU depth pick |
| Build | Xcode project | Plain `Makefile` + Command Line Tools, plus Node.js/Vite for the web panel |
| Windows | Spout build | **Not ported** (macOS only) |

---

## 4. Project layout

```
Linda Vista Mapper/
├── README.md                   ← overview and quick start
├── HANDOFF.md                  ← this file
├── UX-AUDIT.md                 ← usability audit of the 3.1.0 classic sidebar (findings still open)
├── Makefile                    ← all build, test and smoke targets
├── LICENSE                     ← upstream MIT license (Baku Hashimoto), kept for the derived work
├── resources/
│   ├── Info.plist              ← bundle metadata (@VERSION@ filled in by make); id local.lindavistamapper
│   ├── LindaVistaMapper.icns   ← app icon (currently still the original Virtual Mapper icon)
│   └── data/                   ← copied into the bundle's Resources/data
│       ├── Karla-Regular.ttf   ← UI font (from upstream)
│       ├── Karla-OFL.txt       ← font license (must ship with the font)
│       └── default_tex.png     ← UV test chart shown when a source has no frame
├── src/
│   ├── main.mm                 ← NSApplication, window, MTKView subclass (VMView), menus, drag & drop, CLI flags
│   ├── VMApp.h/.mm             ← app core: frame loop, sidebar root, input routing, settings load/save, snapshot capture, panel state/action bridge
│   ├── WebPanel.h/.mm          ← the web panel host: WKWebView docked left, drag-to-resize, collapse rail, JSON bridge to the page
│   ├── AppContext.h            ← shared services (device, window, renderer, data path, runLater)
│   ├── Settings.h/.mm          ← JSON settings tree (NSMutableDictionary wrapper)
│   ├── ImGuiApp.h/.mm          ← ImGui style (palette), custom widgets (PlayToggle, Seekbar, Alert), native dialogs
│   ├── Renderer.h/.mm          ← Metal pipelines and shaders (inline MSL), scene buffers, grid, lines, GPU depth pick
│   ├── SceneLoader.h/.cpp      ← ufbx → world-space meshes, materials, wireframe edges, camera presets
│   ├── Camera.h/.cpp           ← GrabCamera: orbit, dolly, pan around a pivot; projection helpers
│   ├── CameraInfo.h            ← camera preset struct
│   ├── VMMath.h                ← simd helpers (reversed-Z projection, rigid decomposition, Euler)
│   ├── InputScript.h/.mm       ← synthetic input for snapshot tests (--input-script)
│   ├── Managers/               ← one per sidebar section, as in 2.x; each also handles its web panel actions
│   │   ├── BaseManager.h       ← includes handlePanelAction(type, action)
│   │   ├── SceneManager        ← "Scene" section: open FBX, import cameras
│   │   ├── ViewManager         ← "View" section, camera and navigation, visibility, 3D draw order, camera labels
│   │   ├── SourceManager       ← "Source" section: source switching, flip, drag & drop routing
│   │   └── MiscManager         ← "Misc" section: window on top, fullscreen, help
│   └── Sources/
│       ├── BaseSource.h        ← texture() + isBottomUp() contract
│       ├── SyphonSource        ← server list, auto-(re)connect, Metal frames
│       ├── ImageSource         ← ImageIO loader (also used for default_tex.png)
│       └── VideoSource         ← VMVideoPlayer (AVFoundation) + seek bar overlay
├── ui/                         ← the web panel: Vite + React 19 + Tailwind 4 + shadcn/ui (Radix)
│   ├── src/App.tsx             ← panel layout: Stage, Source, Camera, Display, Window sections; collapsed rail
│   ├── src/bridge.ts           ← PanelState / PanelAction types, native bridge, browser preview state
│   ├── src/keys.ts             ← forwards app shortcuts from the web view to the app
│   ├── src/components/ui/      ← shadcn/ui components (generated, then edited by hand)
│   └── dist/index.html         ← build output (gitignored): one self-contained file, copied into the bundle
├── tests/                      ← make test (unit + GPU pick)
├── tools/
│   ├── make_test_scene.py      ← writes an ASCII FBX test stage (optionally in meters)
│   ├── syphon_test_sender.m    ← publishes a GL-oriented test pattern over Syphon
│   ├── make_test_movie.m       ← writes a numbered H.264 test movie
│   └── smoke_test.py           ← make smoke
├── vendor/                     ← pinned third-party sources (see VERSIONS.txt)
│   ├── imgui/  ufbx/  syphon/
│   └── VERSIONS.txt
└── (gitignored, not in the repo: build/, ui/node_modules/, ui/dist/, and optionally upstream/ —
     a reference clone of the original repo, which is where the "upstream/src" paths in this document point)
```

About 5,600 lines of native project code (src, tests and tools) and 1,900 lines of panel code (ui/src, including the generated shadcn components), excluding vendored code.

---

## 5. Architecture

### 5.1 Frame loop (`VMApp::frame`, src/VMApp.mm)

The `MTKView` calls `drawInMTKView` at 60 fps on the main thread. Each frame:

1. `viewManager_.setViewport(points, backingScale)`.
2. Each manager's `update()` runs. SourceManager updates only the active source, which pulls a new Syphon or video frame. ViewManager checks whether the camera still matches the selected preset.
3. ImGui frame: `ImGui_ImplMetal_NewFrame` → `ImGui_ImplOSX_NewFrame` → `ImGui::NewFrame`.
4. `VMApp::drawImGui()` builds the sidebar, and each manager's `drawImGui()` builds its section.
5. `viewManager_.drawCameraLabels(ImGui::GetBackgroundDrawList(), …)` draws camera names (plus the **WALK** indicator, in Walk nav mode) behind the ImGui windows, regardless of `showControl_` — see [6.3](#6-ui-inventory-current-design).
6. One render pass (4× MSAA, reversed-Z depth): `viewManager_.draw()` draws the 3D scene, then `ImGui_ImplMetal_RenderDrawData` draws the UI on top.
7. Present. In snapshot mode, the drawable is copied to a PNG on the configured frame.

The 3D view always fills the whole window. The sidebar is a translucent overlay (`WindowBg` alpha 0.70), so the scene shows through it.

### 5.2 Managers and sources

`BaseManager` mirrors 2.x: `setup(AppContext&)`, `update()`, `loadSettings(Settings&)`, `saveSettings(Settings&)`, `drawImGui()`, `dragEvent(files)`. They are registered in this order, which is also the sidebar order: **Scene, View, Source, Misc**.

`BaseSource` has `name()`, `texture()` (a Metal texture, or nil for "nothing yet"), `isBottomUp()`, `openPath()`, `onActivated()`/`onDeactivated()`, `update()`, `drawImGui()`, and load/save. Source order is **Syphon, Image, Video**, which sets both the radio-button order and the drag & drop probing order.

**UI code is mixed with logic.** As in 2.x, each manager's and source's `drawImGui()` both draws its controls and performs the actions. See [section 8](#8-notes-for-the-redesign) for untangling this.

### 5.3 AppContext and `runLater`

`AppContext` (src/AppContext.h) holds the Metal device, window, view, renderer pointer, `dataPath` (bundle `Resources/data`) and `runLater(fn)`. `runLater` is a `dispatch_async` to the main queue.

**Why `runLater` exists:** modal dialogs (`NSOpenPanel`, the "Name the new camera preset" `NSAlert`) must not run inside an ImGui frame. A button handler therefore defers the dialog until the frame has finished. Any new UI that opens a modal panel must do the same.

### 5.4 Input routing

```
NSEvent
  → ImGui OSX backend (local event monitor; feeds ImGui's input queue, never swallows events)
  → mouse:  VMView (src/main.mm) → VMApp::mouseDown/Dragged/Up/scrollWheel
  → keys:   ImGui's hidden KeyEventResponder (first responder)
            → passes to VMView::keyDown/keyUp when ImGui doesn't want the key
            → VMApp::keyDown/keyUp
  → VMApp gates on ImGui::GetIO().WantCaptureMouse / WantCaptureKeyboard
  → ViewManager (camera, presets, visibility), SourceManager (video keys), MiscManager (fullscreen)
```

- **Mouse capture:** `VMApp::mouseDown` sets `cameraDragging_ = !WantCaptureMouse`. A press over any ImGui window never moves the camera, and the whole drag is handled by whoever got the press. Scroll is ignored while ImGui wants the mouse.
- **Key capture:** shortcuts are ignored while ImGui wants the keyboard (for example while typing in a field), and whenever ⌘, ⌃ or ⌥ is held. Auto-repeat is ignored, except for the video arrow keys and the continuous Walk-mode movement keys (`W`/`A`/`S`/`D`/`Q`/`E`), which must keep registering on every repeat while held.
- **Held-key state:** `spaceDown_`, `handDown_` and the six Walk-mode movement flags (`wDown_`/`aDown_`/`sDown_`/`dDown_`/`qDown_`/`eDown_`) are all reset together when the window loses key status (`windowDidResignKey` → `resetHeldKeys`).

### 5.5 Scene loading (src/SceneLoader.cpp)

ufbx options match what ofxFBX did with the Autodesk SDK:
- `target_axes = right-handed Y-up`, `target_unit_meters = 0.01` (centimeters), `space_conversion = MODIFY_GEOMETRY`.
- `target_camera_axes = right-handed Y-up`. Cameras come out OpenGL-style (looking down −Z), matching 2.x's `cameraMatrixToOf`.
- `generate_missing_normals`, `ignore_animation`, `ignore_embedded`.

Geometry is triangulated and baked into **world space** (`geometry_to_world`), with vertices deduplicated per material part (`ufbx_generate_indices`). Each node is classified by the name prefix of its **own** name (`classifyNodeName`). Wireframe data is the **polygon outlines** (not triangle diagonals), deduplicated by endpoint position.

Camera presets use a pre-order depth-first traversal (same order as 2.x, which matters for the `1`–`9` keys). Each preset stores the vertical FOV (`field_of_view_deg.y`) and an orthonormalized node-to-world matrix.

Load failures keep the current list of loaded files unchanged and show the "Unknown File Format" alert (scenes are loaded additively; see [6.2](#6-ui-inventory-current-design)).

### 5.6 Texture orientation (important if you touch sources)

FBX UVs follow the standard convention, where v = 0 is the **bottom** of the image. Each source declares how its rows are stored:
- `isBottomUp() == false` for Image, Video and the default texture: row 0 is the top of the image.
- `isBottomUp() == true` for Syphon: row 0 is the bottom (OpenGL/IOSurface convention).

`SourceManager::currentTexture(&flipV)` computes `flipV = !bottomUp XOR isFlipTexture`, and the screen shader samples `v' = flipV ? 1 − v : v`. With **Flip Texture Vertically unchecked**, every source maps UV (0,0) to the image's bottom-left. `make smoke` asserts this for image, Syphon and video.

### 5.7 Settings

`Settings` is a small wrapper around a mutable JSON dictionary. `child("key")` creates the node if it's missing, so the same calls work for load and save. Floats and matrices are sanitized to finite values before saving; `NSJSONSerialization` rejects NaN and would otherwise crash on quit.

- Normal runs: `~/Library/Application Support/Linda Vista Mapper/settings.json`, loaded at launch and written in `applicationWillTerminate`.
- ImGui layout (currently just the sidebar width): `imgui.ini` in the same folder.
- With `--settings <file>`, that file is used instead and written back on quit. `imgui.ini` is disabled.
- A snapshot run with no `--settings` never writes the user's settings.

The full schema is in [section 12](#12-settings-schema).

### 5.8 Web panel (default UI)

Launch flags (src/main.mm): the web panel is on by default; `--classic-ui` selects the ImGui sidebar; `--web-ui` is accepted and means the default; `--ui-dev-url <url>` loads the panel from a Vite dev server instead of the bundle (`cd ui && npm run dev`, then `--ui-dev-url http://localhost:5173`) for hot-reload design work. The panel page also runs in a plain browser under `npm run dev`, with a fake preview state (`ui/src/bridge.ts`).

**Layout** (`WebPanel.mm`): `WebPanel::install` replaces the window's content view with a container holding the `WKWebView` panel on the left and the 3D `MTKView` in the rest, so unlike the ImGui sidebar the panel never covers the scene. An 8 pt divider on the panel's right edge resizes it between 280 and 520 pt (the 3D view never gets narrower than 320 pt); dragging below the midpoint between the rail and the minimum width collapses it to a 60 pt icon rail, and the page switches layout by its own width (a `max-[120px]` media query in `App.tsx`). Panel width and collapsed state persist as `panel.width` / `panel.collapsed`. The `C` key sets `showControl_`, which hides the whole panel; the ImGui "Show Control" button (or `C` again) brings it back. (The `setPanelVisible` action exists in the bridge but no control in the page sends it.)

**Bridge**, both directions JSON:
- **App → panel:** every frame `VMApp::panelState()` builds the whole panel state as an `NSDictionary` (types in `ui/src/bridge.ts`, `PanelState`); `WebPanel::pushState` serializes it and calls `window.__vmReceive(state)` only if the JSON changed.
- **Panel → app:** `window.webkit.messageHandlers.vm.postMessage({type, ...})` (`PanelAction` in `bridge.ts`). `ready` is handled by `WebPanel` (it resets the last-pushed state so a reloaded page gets a fresh push); `setPanelVisible` / `setPanelCollapsed` are handled by `VMApp::handlePanelAction`; everything else is offered to each manager's `handlePanelAction(type, action)` in turn (Scene, View, Source, Misc), and the first to return true handles it. Add a new control by adding a `PanelAction` variant, handling it in the owning manager, and (if it shows state) extending `panelState()` and `PanelState`.
- **Optimistic updates:** `bridge.ts` applies continuous controls (drags, sliders, toggles) locally before the app's next push confirms them; one-shot actions that open a native dialog don't need it.
- **Dialogs** still go through `ctx->runLater(...)` (see [5.3](#53-appcontext-and-runlater)); the panel never opens them itself.

**Input:** keys pressed while the web view has focus are forwarded to the app by `ui/src/keys.ts` (`{type: "key", phase, key, repeat}`) unless the panel needs them (typing in a field, an open menu, Tab, or Space/Enter/arrows on a keyboard-focused control). `VMApp::panelKey` replays each one as the key event the 3D view would have received, so every shortcut keeps a single code path. Mouse input over the 3D view is unchanged, and files dropped on the panel are routed to the same handler as drops on the 3D view. Overlays that sit on the 3D view (camera name badge, camera labels, WALK indicator, video seek bar) are still drawn by ImGui (`BaseManager::drawOverlays`); only the sidebar is replaced.

**Build:** `ui/` is a Vite project using `vite-plugin-singlefile`, so `npm run build` produces one self-contained `ui/dist/index.html`; `make` copies it to `Contents/Resources/ui/index.html`. Its text is 15 px root with macOS-sized controls (`ui/src/index.css`). The shadcn/ui components in `ui/src/components/ui/` were generated with the shadcn CLI and then edited by hand (e.g. `input.tsx` forwards a ref; `slider.tsx` was written to match).

**Snapshots:** in `--snapshot` mode the panel is captured with `WKWebView takeSnapshot` and composited with the 3D view (`VMApp::encodeSnapshot`), so the snapshot harness covers the panel too. It can also be inspected live: **Safari → Develop → *this Mac* → Linda Vista Mapper** (macOS 13.3+).

---

## 6. UI inventory (current design)

There are two UIs over the same managers. This section (6.1–6.4) documents the **classic ImGui sidebar** (`--classic-ui`), which is the behavior ported from 2.x: everything is Dear ImGui except the window chrome, menu bar, file dialogs and the camera-name prompt, which are native AppKit. The **web panel**, the default, is described in [5.8](#58-web-panel-default-ui), and its controls are listed in [6.5](#65-web-panel-controls). The window chrome (6.1), overlays (6.3) and 3D view colors (6.4) apply to both.

### 6.1 Window and chrome (src/main.mm)
- Initial content size **1024 × 768 pt**, centered. Resizable, and supports native full screen.
- Title bar is transparent with the title hidden; the window background is black (matches 2.x).
- Accepts file drops (`NSPasteboardTypeFileURL`).
- Menu bar: **App** (About, Hide ⌘H, Hide Others ⌥⌘H, Show All, Quit ⌘Q) and **Window** (Minimize ⌘M, Zoom, Toggle Full Screen ⌃⌘F). There is no File or Edit menu.
- Quitting or closing the window saves settings (`applicationShouldTerminateAfterLastWindowClosed`).

### 6.2 Sidebar: "Control" window (`VMApp::drawImGui`)
- Pinned at (0,0), full window height, width **≥ 250 pt** (starts at 250). The user can drag its right edge to resize, and the width persists via `imgui.ini`.
- Flags: no title bar, no move. Background `WindowBg` = rgba(0.13, 0.14, 0.17, **0.70**).
- **Hide Control** button at the top (same as the `C` key). When hidden, only a transparent **Show Control** button remains at the top-left. The section overlays (camera badge, seek bar) are hidden too, as in 2.x.
- Four collapsing headers follow. Their open or closed state persists as `isGuiOpened` in settings.

#### Scene section (`SceneManager::drawImGui`)
Loading is additive: each added FBX appends its classified meshes to the scene (screens/stages/guides are simply unioned across files; node classification is unaffected and needs no per-file namespacing) rather than replacing what's loaded. A scrollable child region lists every loaded file.

Add FBX and Reload parse the file on a background queue (`dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), …)`): the ufbx parse itself never touches `entries_`, the renderer or ImGui state, and the finished `SceneData` is handed back to the main thread via `ctx->runLater(...)` before anything shared is touched. While a load is in flight, that row shows "Loading..." in place of its path/size text and its own Reload/Remove are disabled (`ImGui::BeginDisabled`); "Add FBX" is disabled globally whenever *any* row is loading, so at most one entry can be appended/replaced at a time. A failed Reload leaves the entry's previous geometry untouched; a failed Add removes its placeholder row — either way the "Unknown File Format" alert is shown.

| Control | Type | Behavior | Persisted |
|---|---|---|---|
| **Add FBX** | button, disabled while any row is loading | `runLater` → `Dialogs::chooseFile("Load Scene File (.fbx)", {"fbx"})` → `addFBX(path)`, which appends a "Loading..." placeholder row immediately and fills it in when the background parse finishes (on failure, shows the alert and removes the placeholder, leaving the list as it was) | `scene.fbxPaths` (array, in list order) |
| "(No Scene)" | text | shown when no files are loaded | — |
| per-entry row: file path, human-readable size (or "Loading..." while that entry's load is in flight) | text | e.g. `/path/stage.fbx`, "1.2mb" (size is read from disk at load time, not persisted) | — |
| per-entry **Import Cameras** | button | shown only if that file has cameras (hidden while loading); appends them to the preset list (`onCameraListImport` → `ViewManager::importCameraList`) | presets saved under `view.camera.list` |
| per-entry "Number: N" | text | that file's camera count | — |
| per-entry **Reload** | button, disabled while that row is loading | re-reads that file from disk on a background queue and rebuilds just that entry when done; on failure shows the alert and keeps the entry's previous data; clears any pending Remove confirmation on every row | — |
| per-entry **Remove** / **Confirm Remove?** | button, disabled while that row is loading | two-click confirm: the first click arms that row ("Confirm Remove?") and disarms every other row; a second click on an armed row drops that entry's meshes and asks `ViewManager::removeCameraList` to drop any presets imported from it (falls back to "(Custom)" if the active preset was one of them, same as **Delete Camera**). Clicking **Add FBX** or **Reload** (any row) also clears a stale confirmation. | — |
| "Unknown File Format" | modal alert | "Failed to load FBX file." | — |

#### View section (`ViewManager::drawImGui`)
| Control | Type | Behavior | Persisted |
|---|---|---|---|
| **Cameras** | tree node (closed by default) | reveals the controls below | — |
| camera combo | combo `##Camera` | "(Custom)", "1: name", "2: name"…; choosing a preset applies it (`applyCurrentCameraInfo`); choosing Custom keeps the current view | `view.camera.index` |
| **Add Camera** | button, disabled unless Custom | `runLater` → native prompt "Name the new camera preset" (default "Camera N"); Cancel adds nothing; saves the current transform and FOV, then selects it | `view.camera.list[]` |
| **Delete Camera** | button, disabled while Custom | removes the selected preset and returns to Custom | — |
| "Coord" | text label | — | — |
| **Pos** | DragFloat3 (speed 1, `%.1f`) | camera world position in cm | `view.camera.current.matrix` |
| **Rot** | DragFloat3 (speed 1, `%.1f`) | Euler degrees shown as (pitch X, yaw Y, roll Z), where R = Ry·Rx·Rz | (same matrix) |
| **Fov** | SliderFloat 0–180 | vertical FOV in degrees (clamped to 0.5–179 when rendering) | `view.camera.current.fov` |
| **Fix Up Direction** | checkbox | keeps the horizon level while orbiting | `view.camera.fixUpDirection` |
| **Visibility** | tree node (closed by default) | 2-column checkboxes: **Cameras, Grid / Guides, Screens / Stages, Wireframe** (alphabetical, as in 2.x) | `view.visibility.*` |
| **Enable Screen Blending** | checkbox | draws screens with the "screen" blend mode and no depth writes | `view.enableScreenBlending` |

Editing Pos, Rot or Fov, or navigating, automatically switches the combo back to **(Custom)** (`ViewManager::update` uses `GrabCamera::matches`).

#### Source section (`SourceManager::drawImGui`)
| Control | Type | Behavior | Persisted |
|---|---|---|---|
| **Syphon / Image / Video** | radio buttons in one row | `select(i)`: previous `onDeactivated()`, new `onActivated()` | `sources.selected` |
| *(Syphon)* server combo | combo `##Server`, full width | lists "App - Server" (or "App"); preview reads "(No Server)" or "(Select Server)"; selecting connects | `sources.syphon.inputName` |
| *(Image)* **Load Image** | button + path text / "(No Image)" | `runLater` → open panel (any file) → load; on failure shows "Unknown Image Format" | `sources.image.path` |
| *(Video)* **Load Video** | button + path text / "(No Source)" | `runLater` → open panel (any file) → load and autoplay; on failure shows "Unknown Video Format" | `sources.video.path` |
| *(Video)* **Close** | button | unloads the movie | — |
| **Flip Texture Vertically** | checkbox | inverts V for all sources (see 5.6) | `sources.isFlipTexture` |

#### Misc section (`MiscManager::drawImGui`)
| Control | Type | Behavior | Persisted |
|---|---|---|---|
| **Show Window On Top** | checkbox | `NSFloatingWindowLevel` vs normal level | `misc.showWindowTop` |
| **Enable Fullscreen** | checkbox | native macOS full screen; the checkbox tracks the real state through window notifications | not persisted (same as 2.x) |
| **Walk Navigation** | checkbox, with a hover tooltip summarizing Walk mode's controls | switches `ViewManager`'s nav mode between Orbit (default) and Walk — WASD+QE movement, hold-right-drag to look; deliberately low-visibility here rather than in the View section — see [7](#7-controls-inventory-mouse-and-keyboard); the always-on **WALK** overlay ([6.3](#6-ui-inventory-current-design)) is what actually surfaces the mode while this checkbox (and the rest of the panel) may be hidden | `view.navMode` ("orbit"/"walk") |
| **Help** | button | opens the Help window | — |

### 6.3 Overlays
| Overlay | Where | Shown when | Code |
|---|---|---|---|
| **Camera name badge** "N: name" | top-right, 10 pt margin, auto-size, no inputs | a preset is active and the sidebar is shown | `ViewManager::drawImGui` (`##CameraName`) |
| **Camera labels** | 3D camera position + (15, −12) pt; Karla 12 px; white at 75% alpha | Cameras visibility on; skipped for cameras behind the view | `ViewManager::drawCameraLabels` (ImGui background draw list) |
| **WALK indicator** "WALK" | bottom-right, 10 pt margin, auto-size; Karla 12 px; white at 75% alpha (same convention as Camera labels) | Walk nav mode is active — unlike the camera-name badge and seek bar above, this is **not** gated on `showControl_`: it's the only way to tell Walk mode is active once the Control panel (and its Misc-section checkbox) is hidden | `ViewManager::drawCameraLabels` (same always-on background draw list as Camera labels, so it survives `showControl_ == false`) |
| **Video seek bar** | bottom-center of the area right of the sidebar; width min(600, free width − 60); height 41; 30 pt above the bottom; bg alpha 0.5 | Video source has a movie loaded and the sidebar is shown | `VideoSource::drawSeekbar` (`##Seekbar`) |
| ├ play/pause toggle | 30 pt wide, drawn icon | | `ImGui::PlayToggle` |
| ├ seek slider | round 18 pt grab over a thin line; dragging pauses and seeks exactly | | `ImGui::Seekbar` |
| └ time display | 60 pt button, click toggles "NNF" (frames) or "MM:SS" | | `sources.video.timeDisplayMode` (1 = frames, 0 = time) |
| **Help** window | auto-size, closable, 2-column table of shortcuts | Help button | `MiscManager::drawHelp` |
| **Alerts** | modal popups with an OK button | load failures | `ImGui::Alert` (src/ImGuiApp.mm) |

### 6.4 Style tokens (src/ImGuiApp.mm, `ApplyCustomStyle`)
Base: `StyleColorsDark()`, then these overrides, ported from 2.x.

**Metrics:** WindowRounding 0 · ScrollbarSize 3 · ScrollbarRounding 0 · FramePadding (6, 4) · ItemSpacing (4, 8) · FrameRounding 2 · GrabRounding 2 · WindowBorderSize 0 · PopupBorderSize 0 · DisabledAlpha 0.25 · popup and alert rounding 2 (pushed locally).

**Font:** Karla Regular **14 px** for the UI and 12 px for camera labels. ImGui 1.92 rasterizes at the Retina scale automatically.

**Palette** (RGBA 0–1):
| Role | Slots | Value |
|---|---|---|
| Text | Text / TextDisabled | (0.86, 0.93, 0.89, 1.00) / (…, 0.58) |
| Panel background | WindowBg | (0.13, 0.14, 0.17, 0.70) |
| Popup background | PopupBg | (0.13, 0.14, 0.17, 0.92) |
| Child background | ChildBg | (0.20, 0.22, 0.27, 0.58) |
| Frames | FrameBg | (0.17, 0.19, 0.23, 0.55) |
| **Accent (teal)** | *Hovered / *Active, TitleBgActive, CheckMark (0.80 alpha) | **(0.00, 0.63, 0.75)**, alpha 0.78–1.00 |
| Soft accent | Button, SliderGrab | (0.47, 0.77, 0.83, 0.14) |
| Headers | Header (collapsing headers, tree hover) | (0.21, 0.26, 0.35, 0.76) |
| Title bars | TitleBg / TitleBgCollapsed | (0.20, 0.22, 0.27, 1.00 / 0.75) |
| Separators | Separator | (0.47, 0.77, 0.83, 0.32) |
| Scrollbar | ScrollbarBg / Grab | (0.20, 0.22, 0.27, 1.00) / (0.47, 0.77, 0.83, 0.21) |
| Selection | TextSelectedBg | (0.00, 0.63, 0.75, 0.43) |
| Modal dim | ModalWindowDimBg | (0.20, 0.22, 0.27, 0.73) |
| Borders | Border / BorderShadow | fully transparent |

**3D view colors** (Renderer): background black · grid lines gray 0.502 at 1 pt, every 1 m out to ±10 m · axes 4 m long at 2 pt (X red, Y green, Z blue) · wireframe white at 2 pt · camera glyphs white at 75% alpha, 1 pt, drawn on top.

### 6.5 Web panel controls

Source: `ui/src/App.tsx`. Sections, top to bottom, under a header ("Linda Vista Mapper" and a collapse button) and above a footer (version and a keyboard-shortcuts tooltip). Every control maps to a `PanelAction` (see `ui/src/bridge.ts`) handled by the manager named in the last column, and persists through that manager's settings exactly as the classic control does ([section 12](#12-settings-schema)).

| Section | Controls | Notes | Handled by |
|---|---|---|---|
| **Stage** | **+** (Add FBX); an empty-state drop target; per-file card with name, size, folder (full path on hover), a **Screens** or amber **No screens** badge, **Import N cameras**, **Reload**, **Remove** | Add is disabled while any file loads; cards show "Loading…" while parsing; Remove is a two-click confirm (the second click is the check icon, disarmed on blur). "No screens" appears when no mesh name starts with `screen` | `SceneManager` |
| **Source** | Syphon / Image / Video selector; status line with a colored dot | Syphon: server picker. Image: Load Image. Video: Load Video, Close, play/pause, frame step, seek. Flip Texture Vertically | `SourceManager` |
| **Camera** | preset select ("Custom view", then presets with `1`–`9` hints); **+** save current view; trash delete preset; Position and Rotation (three scrubbable number fields each); Field of view slider (1–179°); Fix up direction; Navigation Orbit / Walk toggle, with a one-line hint for the active mode | Number fields scrub by dragging (1 unit per pixel) or take typed values; editing any of them switches to Custom view. Add is enabled only on Custom view, delete only on a preset | `ViewManager` |
| **Display** | switches for Screens, Stage geometry, Guides (`G`), Wireframe (`X`), Floor grid, Camera markers; Screen blending | | `ViewManager` |
| **Window** | Always on top; Enter / Exit full screen (`F`) | Full screen state tracks the real window state | `MiscManager` |

**Collapsed rail** (60 pt): expand button, one icon each for Stage (with a file-count badge, amber if a file has no screens), Source (with the status dot) and Camera (with the active preset number), the six layer toggles, and a shortcuts icon. Hovering uses native `title` tooltips.

Behavior differences from the classic sidebar: Cameras/Visibility are not hidden behind collapsed trees, Walk mode lives in the Camera section, the Help window is replaced by the footer's shortcut tooltip, and the file list shows the filename and folder separately instead of a truncated path.

---

## 7. Controls inventory (mouse and keyboard)

There are two camera navigation modes, `view.navMode`, toggled by the **Walk Navigation**
checkbox tucked into the Misc section (deliberately low-visibility, not in the View
section's camera controls — see [6.2](#6-ui-inventory-current-design)):
- **Orbit** (default): everything below under "Orbit mode" — left-drag orbit, right-drag
  dolly, middle/H-drag pan, scroll-zoom, all around the picked pivot. Unchanged from
  pre-Walk-mode behavior.
- **Walk**: WASD+QE fly the camera continuously while held; right-drag looks around in
  place instead of dollying. `ViewManager::setNavMode` resets any in-progress drag and
  held-key state on every switch, so there's no leftover drift when you switch back.

While walking, the always-on **WALK** overlay ([6.3](#6-ui-inventory-current-design)) is
the persistent reminder that you're in Walk mode — where WASD+QE fly the camera and
right-drag looks around instead of dollying — and it stays visible even with the Control
panel (and the checkbox above) hidden; the checkbox itself also has a hover tooltip
saying the same thing.

### Mouse (3D view only; ignored over any ImGui window)
| Input | Action | Implementation / tuning |
|---|---|---|
| Left drag | **Orbit** around the point under the cursor (both modes) | `GrabCamera::orbit`: 180° per shorter view dimension; drag right moves the camera left ("grab" feel); with Fix Up Direction, yaw uses world up, the horizon stays level, and poles are blocked |
| Right drag — **Orbit mode** | **Dolly** toward or away from the picked point | `GrabCamera::dolly(pivot, exp(dy·0.005))`: drag up zooms in, drag down zooms out |
| Right drag — **Walk mode** | **Look** around in place (yaw/pitch around the camera's own position, not a pivot) | `GrabCamera::look`: 180° per shorter view dimension, same scale as orbit; pitch clamped to ±89°; roll always reset to 0 |
| Middle drag | **Pan** (both modes) | `GrabCamera::pan`: exact grab, the picked point follows the cursor |
| `H` or `Space` held + left drag | **Pan** | same as middle drag (for trackpads) |
| Scroll | **Zoom toward the cursor** | factor 0.99^delta, where delta = scrollingDeltaY × (trackpad ? 0.1 : 1), clamped to ±50 per event; sign follows the system scroll direction, like 2.x |
| Drop 1 file | `.fbx` → **add** to the scene (same as **Add FBX**, including being ignored while a Scene load is already in flight); other files → try Image, then Video, and switch to whichever worked | `SceneManager::dragEvent`, `SourceManager::dragEvent` |

**Pivot selection** (`ViewManager::pickPivot`, runs on each press or scroll):
1. A GPU depth pick of the visible stages, guides and screens (`Renderer::pickDepth`: a 1×1 render with a zoomed projection, read back synchronously).
2. Otherwise, the floor plane y = 0 if the ray hits it within 1 km.
3. Otherwise, a point along the ray at the last pivot distance.

(Still run unconditionally on every press in Walk mode too, even though a right-drag-look
doesn't use the result — harmless, just an unused pick.)

### Keyboard (ignored while typing in a field or when ⌘, ⌃ or ⌥ is held)
| Key | Action | Handler |
|---|---|---|
| `1`–`9` | Switch to camera preset N (if it exists) | `ViewManager::keyDown` |
| `R` | Reset camera to (300, 100, 300) looking at the origin, FOV 40, Fix Up on | `ViewManager::keyDown` |
| `X` | Toggle wireframe (both nav modes — the sole wireframe-toggle key; `W` has no wireframe meaning) | `ViewManager::keyDown` |
| `W` / `A` / `S` / `D` / `Q` / `E` — **Walk mode** | Move forward / strafe left / move back / strafe right / move down / move up, continuous while held, scaled by elapsed frame time (~600 cm/s default). No binding, and no effect, in Orbit mode. | `VMApp::keyDown/keyUp` (held state) → `ViewManager::update` |
| `G` | Toggle guides | `ViewManager::keyDown` |
| `C` (on key up) | Toggle the control panel | `VMApp::keyUp` |
| `F` | Toggle native full screen | `VMApp::keyDown` → `MiscManager::toggleFullscreen` |
| `Space` tap | Play/pause video (only when the Video source is active; ignored if Space was used to pan) | `VMApp::keyUp` → `SourceManager::toggleVideoPlayback` |
| `←` / `→` (repeat allowed) | Step the video one frame back or forward (pauses; Video source only) | `VMApp::keyDown` → `SourceManager::stepVideo` |
| `H` held | Pan modifier | `VMApp::keyDown/keyUp` |

Letter keys are matched case-insensitively.

`W`/`A`/`S`/`D`/`Q`/`E` are tracked as continuous held state in `VMApp` exactly like
`spaceDown_`/`handDown_` (set on `keyDown`, cleared on `keyUp` and on
`windowDidResignKey`/`resetHeldKeys`), but — like the video arrow keys — they are **not**
suppressed on auto-repeat, since continuous movement needs the down-state for as long as
the key is physically held. `ViewManager::update()` reads this held state every frame
(via `setMoveKeysHeld`) and, only in Walk mode, moves the camera by elapsed wall-clock
time × ~600 cm/s, normalizing the combined WASD+QE direction so holding several keys at
once doesn't move faster than one.

---

## 8. Notes for the redesign

This section was written for the redesign that produced the web panel ([5.8](#58-web-panel-default-ui)). It is still the checklist for any further UI work; the notes below were written against the classic ImGui sidebar, and where the web panel changes the picture it says so.

### 8.1 What the current UI depends on
- **With the web panel, AppKit owns input arbitration for the panel area.** The 3D view is a separate `NSView` beside the `WKWebView`, so clicks on the panel never reach it (the `WantCaptureMouse` gate only matters for the ImGui overlays, which are small). Keyboard focus in the web view is handled by forwarding keys to the app (`ui/src/keys.ts`, `VMApp::panelKey`); `VMApp::drawImGui` skips the sidebar when the panel is active but keeps `drawOverlays()`.
- **ImGui owns input arbitration (classic sidebar).** Camera input is gated on `WantCaptureMouse` and shortcuts on `WantCaptureKeyboard`. If panels move to native AppKit or SwiftUI views, AppKit hit-testing takes over this job. You'd then drop the gate or keep ImGui for overlays only.
- **Keyboard nav is on, with a deliberate carve-out.** `ImGuiConfigFlags_NavEnableKeyboard` is set (Tab/Shift-Tab/Enter/Space/arrows reach every sidebar control, including the Scene section's scrollable child — see its `ImGuiChildFlags_NavFlattened`). Left at its default, `io.NavActive` alone would force `WantCaptureKeyboard` true merely because the sidebar exists with nav focus, swallowing every VMApp shortcut (WASD/QE, 1-9, R, G, F, C, Space) whenever it's open; `io.ConfigNavCaptureKeyboard = false` (VMApp.mm) turns that off while leaving the "typing in a field" gate (`ActiveId`/modal) intact. Any future addition here that also enables Nav should re-check this interaction.
- **ImGui's OSX backend installs a window-wide local event monitor** and makes its `KeyEventResponder` the first responder. Keys reach `VMView` only through that responder's `[super keyDown:]`. If ImGui is removed entirely, make `VMView` (or a menu) receive keys directly.
- **Camera labels** use ImGui's background draw list. Without ImGui they'd need another text path (a CoreText layer or Metal text).
- **Error alerts** are ImGui modals. Native `NSAlert` would also work; it must go through `runLater`.
- **Modal dialogs** must always go through `ctx->runLater(…)`, never be called mid-frame.
- **Sidebar width** is persisted by ImGui (`imgui.ini`); section open states by `isGuiOpened`.

### 8.2 Actions a new UI must be able to trigger (and where they are today)
The "Today" column describes the classic ImGui code paths. All of these actions are also reachable from the web panel through each manager's `handlePanelAction`, which needed small public methods added (for example `ImageSource::isLoaded`/`path`, `VideoSource::close`/`isPlaying`/`totalFrameCount`/`seekToFrame`, `SyphonSource::serverNames`/`connectedIndex`/`selectServer`, and `ViewManager::requestAddCamera`/`deleteCurrentCamera`, shared with the ImGui buttons). A further UI should follow the same pattern.

| Action | Today |
|---|---|
| Add a scene file (dialog or path), reload or remove one | `SceneManager::addFBX`/`reloadEntry`/`removeEntry` (private), called from its `drawImGui` and `dragEvent` |
| Import FBX cameras | `onCameraListImport` callback → `ViewManager::importCameraList` |
| Select, add or delete a camera preset | inline in `ViewManager::drawImGui`; `applyCurrentCameraInfo()` (private) |
| Reset camera | `ViewManager::resetCamera()` (private); `R` key |
| Read or write camera position, rotation, FOV, fix-up | `ViewManager::cam_` (private `GrabCamera`) |
| Toggle a visibility layer | `ViewManager::visible(key)` (private) |
| Screen blending | `ViewManager::enableScreenBlending_` (private) |
| Switch source | `SourceManager::select(i)` (private) |
| Pick a Syphon server | `SyphonSource::connect(i)` (private); list in `servers_` |
| Load an image or video | `ImageSource::load` / `VideoSource::load` (private); `openPath()` is public |
| Play/pause, step, seek, time mode | `VideoSource::togglePlayback`, `stepFrames` (public); seek via `VMVideoPlayer seekToFrame:` inside `drawSeekbar` |
| Flip texture | `SourceManager::isFlipTexture_` (private) |
| Switch nav mode (Orbit/Walk), read continuous WASD+QE movement | `ViewManager::setNavMode`/`navMode()` (public); `MiscManager::isWalkModeActive`/`setWalkModeActive` callbacks wire the Misc checkbox to it; held-key state is tracked in `VMApp` and passed in each frame via `setMoveKeysHeld` |
| Window on top / fullscreen | `MiscManager::applyWindowOnTop` (private) / `toggleFullscreen` (public) |
| Show or hide the control panel | `VMApp::showControl_` |

### 8.3 Build constraints to design around
- **Node.js is a build dependency.** `make` runs `npm install` / `npm run build` in `ui/` whenever `ui/src` (or its config) changes, and fails without `npm`. The built panel is a single HTML file, so there are no runtime dependencies or network access (the panel is loaded from a file URL with read access limited to `Resources/ui`).
- **No Xcode:** no Interface Builder, storyboards, asset catalogs or offline `.metal` compilation. Everything is code plus the Makefile. `swiftc` is available through the Command Line Tools, so Swift/SwiftUI is possible, but it would need a mixed-language build step. Objective-C++ with AppKit is the lowest-friction native option.
- New source files are picked up automatically by the Makefile wildcards (`src/*.mm`, `src/*.cpp`, `src/Managers/*.mm`, `src/Sources/*.mm`). Put new framework links in `FRAMEWORKS`.
- **Don't name a header `Math.h`** (or anything that collides with a system header ignoring case). The filesystem is case-insensitive, and `-Isrc` would shadow `<math.h>`.

### 8.4 Keep the tests in step with the layout
**`tools/smoke_test.py` runs the app with `--classic-ui`.** Its fixed coordinates are calibrated for the ImGui sidebar, so **nothing automated covers the web panel's layout or controls yet**; it has only been checked through the snapshot harness (see [10](#10-verification-status) and [11](#11-testing-toolkit), including the `js` script command, which can click a panel control by its `data-testid`). Porting the panel checks to `js` commands is the obvious next test work. Until then, a regression in the web panel will not fail `make smoke`.

`tools/smoke_test.py` clicks and drags at **fixed coordinates** (points from the top-left of a 1024×768 content view):
- Orbit drags from (520, 380) to (720, 380). This is 3D view space and must stay free of UI.
- The panel-drag check drags (150 → 220, 700) and **expects that area to be UI**, so the camera must not move.
- Pixel checks sample the center screen seen through the "Front" preset (x 0.29–0.71, y 0.35–0.65 of the image). The sampled points must not be covered by UI.
- The Scene section's Remove/Confirm Remove? checks click at the fixed point (105, 191) — the first row's Remove button in the default two-entry test fixture. This is the most layout-fragile of the fixed coordinates, since it depends on the Scene header being the first open section and on that row's exact vertical position within the scrollable file list.

If the classic sidebar's layout changes, update these coordinates. The snapshot harness (section 11) is the way to verify UI changes visually.

### 8.5 Behaviors worth preserving (existing users rely on them)
The `screen*`/`guide*` naming, FBX cameras importable as presets, the `1`–`9`/R/X/G/C/F shortcuts, orbit/dolly/pan around the point under the cursor, texture flip semantics, and Syphon naming as "App - Server". Orbit stays the default nav mode with all of the above unchanged; Walk ([7](#7-controls-inventory-mouse-and-keyboard)) is an opt-in toggle that only changes behavior once a user turns it on.

---

## 9. Differences from Virtual Mapper 2.3.1

| Area | 2.3.1 | Rebuild | Why |
|---|---|---|---|
| **Flip Texture Vertically** | Standard FBX UVs showed upside down unless checked | Correct when **unchecked**; checking inverts | ofxFBX passed UVs raw into a top-down texture convention |
| Settings | XML inside the app bundle | JSON in `~/Library/Application Support/Linda Vista Mapper/`; 2.x settings are not imported (and neither are the settings of pre-rename builds, which lived in a `Virtual Mapper` folder there) | Writing into a signed bundle is wrong and breaks the signature |
| Control UI | ImGui sidebar overlaying the 3D view | Web panel (React + shadcn/ui) docked beside the 3D view, resizable and collapsible to a rail; the ImGui sidebar remains as `--classic-ui` | See [5.8](#58-web-panel-default-ui); the audit's "panel covers 24% of the view" finding no longer applies to the default UI |
| Wireframe key | `W` | `X` (`W` no longer toggles it) | `W` is Walk mode's forward key, and one key meaning two things depending on mode was too easy to trip over |
| Display | Rendered at 1× and upscaled (TODO in 2.x README) | Native Retina | — |
| Syphon | Choose each time; restoring at launch was unreliable | Remembers the server by name; reconnects when it appears or restarts; "(No Server)"/"(Select Server)" | Senders often start after the viewer |
| Failed loads | Cleared the current scene or image | Scene and image stay loaded; a failed video load still closes the current movie, as in 2.x | — |
| Lighting | One-sided (back faces dark) | Two-sided headlight | Forgiving of flipped normals and single-sided guides |
| Wireframe | Triangle edges | Polygon outlines | Cleaner for mapping |
| Far clipping | 100 m | Infinite (reversed-Z) | Large venues don't clip |
| Scene loading | One FBX at a time; loading a new one replaced it | Additive and multi-file: **Add FBX** appends to the scene, and each loaded file gets its own Reload/Remove/Import Cameras | Composite stages built from several files |
| Camera navigation | Orbit only (left-drag orbit, right-drag dolly, middle/H-drag pan) | Orbit (default, unchanged) plus an opt-in **Walk** mode: WASD+QE fly, right-drag looks in place | Free-roam traversal of large venues |
| Camera labels | Could appear mirrored for cameras behind the view | Hidden when behind | — |
| Space key | Always toggled video, even while panning | Tap toggles, drag pans | — |
| Video keys | Worked on the hidden player too | Only when the Video source is active | — |
| Shortcuts while typing | Fired (e.g. typing "2" switched cameras) | Suppressed | — |
| Scroll over the panel | Zoomed the camera too | Scrolls the panel only | — |
| Window on top | `CGShieldingWindowLevel` (above everything) | Floating level | Keeps system UI and dialogs usable |
| Fullscreen | GLFW borderless | Native macOS full screen (own Space) | — |
| Add Camera → Cancel | Still added a preset | Adds nothing | — |
| Open Scene dialog | Any file | Filtered to .fbx | — |
| Orthographic cameras | Imported with a bogus FOV | Skipped | 2.x README said they're unsupported |
| Help | Partial list | Adds Scroll, Space pan, video keys (classic UI); the web panel shows a shortcut list in its footer tooltip instead of a Help window | — |
| Misc | Alert typos; overlays shared one ImGui window ID | Fixed | — |
| Platform | macOS (Intel) + Windows (Spout) | macOS arm64 only | — |
| Name / version / bundle id | Virtual Mapper 2.3.1 / com.baku89.virtualmapper | Linda Vista Mapper 3.1.0 / local.lindavistamapper (executable `LindaVistaMapper`) | Avoids clashing with an installed original. The bundle id is a placeholder; change it to a reverse-DNS id you own before distributing |

---

## 10. Verification status

**Automated (rerunnable):**
- `make test`:
  - Node-name classification.
  - FBX world bounds, UV corners, normals and materials.
  - Camera presets (pose and FOV) and cm/m unit conversion.
  - Camera math: Euler round-trip, preset matching, project/unproject, orbit keeps the pivot, pan grab, dolly.
  - **GPU pick** on screen, pillar, floor and guide, with hidden layers ignored.
  - Composite scene merging: merging two loaded files gives the union of their meshes, wireframe and cameras, not a replacement.
- `make smoke`, 24 checks, **all on the classic ImGui UI** (`--classic-ui`; see [8.4](#84-keep-the-tests-in-step-with-the-layout)):
  - Image, Syphon and video orientation.
  - Orbit via real events changes the camera, and the result is saved on quit.
  - The `X` key toggles the wireframe, in both nav modes.
  - A drag over the panel doesn't move the camera.
  - Scene Remove needs a second confirming click, and clicking Reload in between clears a pending confirmation.
  - Walk mode: the WALK indicator appears only in Walk mode and survives the Control panel being hidden; holding `W` moves the camera forward; right-drag looks around in place without dollying.

**Checked by snapshot during the rebuild:**
- Default state; test stage through the Front, Top and overview cameras; wireframe; glyphs and labels.
- Syphon: auto-connect from settings, and reconnect after the sender quit and restarted.
- Video: autoplay; the frame counter matches the picture; pause; ±frame stepping.
- Right-drag and scroll zoom, H-pan, Hide Control click, `2` key.
- Cameras, Visibility and Help panels.
- Settings round-trip: the restored view matched to within 0.001/255 mean pixel difference.
- ufbx corpus: **701/701** valid FBX files load (Maya, Blender, 3ds Max, MotionBuilder…; FBX 6.1–7.7, ASCII and binary). 853 intentionally corrupted fuzz files were rejected without crashes. Slowest load: 46 ms.

**Web panel (snapshot harness only, no automated checks):** each control group (Stage, Source, Camera, Display, Window, the collapsed rail) was checked visually while it was wired up, using the app's own `--snapshot` / `--settings` harness. The panel's actions are exercised by hand, not by `make smoke`.

**Not yet verified:**
- A clean build and a full `make test` / `make smoke` run on a fresh checkout of this repository (the last full run was in the original working tree).
- The web panel under real mouse and keyboard use (scrub fields, resize/collapse drag, key forwarding while a field is focused, drops on the panel).
- The owner's real **Cinema 4D** scenes.
- Real senders: After Effects Syphon plugin, Resolume, VDMX, TouchDesigner.
- File dialogs and Finder drag & drop by a human (these can't be scripted here).
- Fullscreen and window-on-top by a human.
- Non-Retina and multi-monitor setups.
- The Intel (universal) build.

---

## 11. Testing toolkit

### Snapshot harness (built into the app; hidden CLI flags)
```sh
APP="build/Linda Vista Mapper.app/Contents/MacOS/LindaVistaMapper"
"$APP" --settings fixture.json \          # use this settings file (and write it back on quit)
       --classic-ui \                     # optional: the ImGui sidebar instead of the web panel (the default)
       --snapshot out.png \               # render, save the window contents as PNG, quit
       --snapshot-frames 45 \             # frame to capture (60 fps timer; default 90)
       --input-script input.txt           # optional synthetic input
```
- In snapshot mode the window floats on top and a timer drives frames. Otherwise an occluded window stops drawing, and macOS may refuse to activate an app launched from a terminal.
- The PNG is the Retina drawable (2048×1536 for the default window). With the web panel, the panel's own snapshot is composited into it.
- No Screen Recording or Accessibility permission is needed.

**Input script** (src/InputScript.h): one command per line, `<frame> <command> [args]`. Coordinates are **points from the top-left of the 3D view**, which is the whole content view in the classic UI but starts to the right of the panel with the web panel.
```
10 move 520 380              # mouse moved (lets ImGui update hover)
12 down left 520 380         # also: right
13 drag left 540 380
23 up left 720 380
30 key w                     # key down + up; also: keydown h / keyup h
40 key space                 # names: space, left, right, tab, enter (return also accepted)
45 key shift-tab             # any key name can be prefixed "shift-" to hold Shift as well
50 scroll 520 380 100        # precise (trackpad-style) scroll delta
60 js document.querySelector('[data-testid="vis-wireframe"]').click()   # web panel: run JavaScript in the panel
```
The `js` command runs the rest of the line in the web panel, which is how a script clicks a panel control by its `data-testid` (the panel's controls carry them, e.g. `add-camera`, `nav-walk`, `vis-guides`, `load-video`).
Tips:
- Clicking an ImGui button needs a `move` first, and `down`/`up` on different frames.
- Mouse and scroll events go through `NSApp sendEvent:`, so ImGui's monitor sees them. Key events go through `[window sendEvent:]` to the first responder.
- `tab`/`shift-tab`/`enter` drive ImGui's own keyboard nav (moving focus, activating a button), not just VMApp's letter-key shortcuts — this is what scripts the Scene section's Tab/Shift-Tab/Enter keyboard-nav path (see [8.1](#8-notes-for-the-redesign)). They carry the real macOS virtual key code, since ImGui's OSX backend maps keys that way rather than by character.

### Dev tools
- `python3 tools/make_test_scene.py out.fbx [--meters]`: test stage with `floor` and `pillar` (stage), `screen_center` and `screen_left` (screens with standard UVs), `guide_frame` (emissive yellow), and cameras `Front` (0, 120, 600, FOV 40) and `Top` (0, 900, 0, FOV 60).
- `build/syphon_test_sender [seconds]`: server "syphon_test_sender - Test Pattern". A correct receiver shows a red band on top, blue at the bottom, a green stripe on the left, and a white bar sweeping left to right.
- `build/make_test_movie out.mov [frames] [fps]`: the same bands, with the frame number in the middle.

---

## 12. Settings schema

`~/Library/Application Support/Linda Vista Mapper/settings.json` (keys mirror the 2.x XML):
```jsonc
{
  "showControl": true,
  "scene":   { "isGuiOpened": true, "fbxPaths": ["/path/stage.fbx", "/path/props.fbx"] },
  "view": {
    "isGuiOpened": true,
    "visibility": { "cameras": true, "grid": true, "guides": true,
                    "screens": true, "stages": true, "wireframe": false },
    "camera": {
      "index": 0,                     // 0 = Custom, N = preset N (1-based)
      "fixUpDirection": true,
      "current": { "matrix": [16 floats], "fov": 40 },
      "list": [ { "name": "Front", "matrix": [16 floats], "fov": 40 } ]
    },
    "enableScreenBlending": false,
    "navMode": "orbit"               // "orbit" (default) or "walk" -- see section 7
  },
  "sources": {
    "isGuiOpened": true,
    "selected": 0,                    // 0 Syphon, 1 Image, 2 Video
    "isFlipTexture": false,
    "syphon": { "inputName": "App - Server" },
    "image":  { "path": "/path/image.png" },
    "video":  { "path": "/path/movie.mov", "timeDisplayMode": 1 }   // 1 frames, 0 MM:SS
  },
  "misc": { "isGuiOpened": true, "showWindowTop": false },
  "panel": { "width": 280, "collapsed": false }   // web panel: expanded width in pt (280–520), rail or full
}
```
Matrices are column-major camera-to-world transforms, with translation at indices 12–14 in cm; the camera looks down −Z (same layout as `ofMatrix4x4::getPtr`).

**Breaking change (3.1.0):** `scene.fbxPath` (a single string) became `scene.fbxPaths` (an array), for composite loading. The old key is no longer read; a settings file written by an earlier 3.x build resolves to no entries rather than crashing, the same "nothing loaded" fallback as a missing key.

---

## 13. Rendering details

- **Formats:** BGRA8Unorm color with an sRGB-tagged layer, Depth32Float, **4× MSAA**, 60 fps.
- **Depth:** reversed-Z with an infinite far plane (`depth = near / distance`, compare Greater, clear 0). Near plane is 1 cm.
- **Draw order** (`ViewManager::draw`), each layer only if visible:
  1. stages (lit)
  2. guides (lit)
  3. screens (source texture; alpha blend, or "screen" blend with no depth writes)
  4. wireframe
  5. grid and axes
  6. camera glyphs (no depth test)
  7. ImGui (the overlays, and the sidebar in classic mode; the web panel is a separate view beside the 3D view)
- **Lighting** (`lit_fragment`): headlight at the camera, `emission + ambient·0.2 + diffuse·N·L + specular·(N·H)^shininess`, two-sided, per pixel. This mirrors 2.x's fixed-function OpenGL light.
- **Lines:** screen-space quads per segment (instanced), with widths in points × backing scale. They're clipped against the near plane in the vertex shader, and wireframe and grid get a small depth bias so they draw over coplanar surfaces.
- **No scene loaded:** a 1 m × 1 m placeholder screen on the floor, plus a 10 cm white grid as its "wireframe".
- **Shaders** are inline MSL in `Renderer.mm`, compiled at runtime (`newLibraryWithSource`). Uniform struct layouts are mirrored in C++ (one `static_assert`).
- **Screen texture sampling:** linear filtering, clamp to edge, no mipmaps (same as 2.x).

---

## 14. Known limitations and backlog

These were deliberately not done in this phase; the list isn't a plan.
- No Windows/Spout version. The app isn't notarized (needs an Apple Developer ID). Not tested as a universal build.
- FBX: animation, lights and material textures are ignored; orthographic cameras are skipped (all as in 2.x). Screen-mesh classification is case-sensitive.
- No mipmaps on screen textures, so detailed content can shimmer at grazing angles (same as 2.x).
- Trackpad: no pinch-to-zoom, and ⌃-click isn't mapped to right-click.
- No File or Edit menu, and no recent-files list. Files can't be opened by dropping them on the Dock icon (no document types declared).
- Window size and position aren't remembered; it always opens at 1024×768, centered, as in 2.x.
- Video audio plays (as in 2.x). There's no mute control.
- **Planned, not yet built:** an FPS/frame-time readout, and render effects (Bloom, fog). Both are explicitly deferred by the owner, not forgotten — they're the next additions on top of the Walk-mode and composite-scene-loading work in this version.
- **Open usability findings:** [`UX-AUDIT.md`](UX-AUDIT.md) lists what is still outstanding. It was written against the classic sidebar; some findings are already addressed by the web panel (filenames and folders are shown separately; a "No screens" badge covers part of P0 #1; Syphon says "Waiting for Syphon Sender"; Walk mode moved to the Camera section; the panel no longer covers the 3D view), and others still apply (as of the audit and not re-tested since: a missing FBX gets the wrong error and is dropped from settings; Delete Camera, in both UIs, still deletes without confirming; there are no File/View menus).
- **App icon and identity:** `resources/LindaVistaMapper.icns` is still the original Virtual Mapper icon, and the bundle id (`local.lindavistamapper`) is a placeholder.
- **Settings are not migrated** from the `Virtual Mapper` Application Support folder used by builds before the rename; copy `settings.json` across by hand if needed.
- **Tests:** no automated coverage of the web panel (see [8.4](#84-keep-the-tests-in-step-with-the-layout)).

---

## 15. Environment gotchas

These come from the machine the project was developed on; check them first if something misbehaves elsewhere.

- macOS 26.7.1, arm64, **Command Line Tools only** (no full Xcode); SDK `MacOSX26.5.sdk`.
- **`make` needs `npm` on the PATH.** If it stops at `cd ui && npm run build` with `npm: command not found`, install Node.js (or make it visible to non-interactive shells; a Node installed through nvm is usually only on the PATH of interactive shells).
- The shell is **zsh**: unquoted variables don't word-split (`$OBJS` stays one argument), and `?` in URLs must be quoted.
- The filesystem is **case-insensitive**. `src/Math.h` shadowed `<math.h>` and broke the build, so it's now `VMMath.h`.
- `make clean` deletes `build/` only; `ui/node_modules/` and `ui/dist/` are left in place.
- When launched from a terminal, macOS 14+ may not bring the app to the front. Use `open` / `make run` for normal use.

---

## 16. Dependencies and licenses

| Component | Version | License | Location |
|---|---|---|---|
| Dear ImGui (core + Metal/OSX backends) | v1.92.9 | MIT | `vendor/imgui/LICENSE.txt` |
| ufbx | v0.23.1 | MIT or Public Domain (your choice) | `vendor/ufbx/LICENSE` |
| Syphon-Framework (client + server base only) | master `f4761677` (2026-09-21) | BSD 2-clause | `vendor/syphon/License.txt` |
| Karla Regular font | 1.000 (2011, Jonathan Pinhorn) | SIL OFL 1.1 | `resources/data/Karla-OFL.txt` |
| Virtual Mapper (original design, icon, UV chart, behavior) | 2.3.1 | MIT © 2015 HASHIMOTO Baku | `LICENSE` |
| Web panel toolchain and libraries: React, Radix UI, Tailwind CSS, shadcn/ui components, lucide-react, Vite, TypeScript | see `ui/package.json` and `ui/package-lock.json` | MIT / ISC (see each package) | `ui/node_modules` after `npm install`; built into one HTML file, bundled in `Contents/Resources/ui/` |
| Geist variable font (`@fontsource-variable/geist`, used by the web panel) | `ui/package.json` | SIL OFL 1.1 | embedded in the built `ui/dist/index.html` |

Exact revisions are in `vendor/VERSIONS.txt`. To update a dependency, replace its files in `vendor/` and rebuild. The Syphon subset leaves out the OpenGL and Metal *server renderers*, whose `.metal` shaders need Xcode.

---

## 17. Upstream-to-rebuild file map

The original source is in `upstream/src`.

| Upstream (openFrameworks) | Rebuild |
|---|---|
| `main.cpp`, `WindowUtils/*` | `src/main.mm` (window, title bar, level), `MiscManager` |
| `ofApp.*` | `src/VMApp.*` |
| `ImGuiApp.h` | `src/ImGuiApp.*` (the classic sidebar); the web panel (`src/WebPanel.*`, `ui/`) has no upstream counterpart |
| `ofxAdvancedXmlSettings.h` | `src/Settings.*` |
| `ofxAdvancedGrabCam.h` + ofxGrabCam | `src/Camera.*`, `ViewManager` mouse handling, `Renderer::pickDepth` |
| `ExtendedFBXManager.h` + ofxFBX | `src/SceneLoader.*`, `Renderer` |
| `CameraInfo.h` | `src/CameraInfo.h` |
| `Manager/*` | `src/Managers/*` (same four managers) |
| `Source/*` (Syphon, Image, Video, Spout) | `src/Sources/*` (Spout dropped) |
| `bin/data/*` | `resources/data/*` (Karla, default_tex.png; FiraCode dropped as unused) |
| `bin/data/alpha-mask.*` shaders | dropped (unused in 2.x) |
