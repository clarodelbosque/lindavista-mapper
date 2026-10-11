# Linda Vista Mapper: UX audit

- **Date:** 2026-09-30, against version 3.1.0 (commit `f7ca215`).
- **Purpose:** input for the UI and controls redesign (see [HANDOFF.md §8](HANDOFF.md#8-notes-for-the-redesign)).
- **Scope note:** this audit evaluated the **classic ImGui sidebar** (then the only UI; the app was still called Virtual Mapper). The web panel that is now the default UI addresses some findings (#3 filenames, #4 the panel covering the view, part of #1, #6's wording, #8's Walk placement) and not others. [HANDOFF.md §14](HANDOFF.md#14-known-limitations-and-backlog) tracks which. The findings and scores below are unchanged from the original audit.

**How it was evaluated:**
- An expert review against Nielsen's 10 usability heuristics, step-by-step walkthroughs of 6 tasks, and a WCAG contrast check.
- The real app was rendered in 11 states using the snapshot harness (`--settings`/`--snapshot`/`--input-script`, see [HANDOFF.md §11](HANDOFF.md#11-testing-toolkit)): first run, loaded scene, panels expanded, Help, video, panel hidden, Walk mode, a bad FBX, a missing FBX, a Syphon sender that isn't running, and Remove waiting for confirmation.
- The code was read alongside the renders.

**Not covered:** real users, the owner's Cinema 4D scenes, real Syphon senders, hover states, native file dialogs, multiple monitors.

---

## Score: 58/100 (estimate)

| Part | Score | Basis |
|---|---|---|
| Heuristics | 42 | 23 of a possible 40 severity points |
| Tasks | 53 | 2 of 6 fail, 3 have friction, 1 passes |
| Manipulative design | 100 | None found |

Weighted 40/40/20.

The core experience works and feels like a tool for experts. It loses points on first run, on failures, and because the panel covers the 3D view. The problems are silent failures and knowledge the app never tells you.

---

## P0: blocks the core task

### 1. Nothing explains why content doesn't appear
If no mesh name starts with `screen`, the FBX loads and the geometry shows, but the content never appears and nothing says why.
- The match is case-sensitive (`src/SceneLoader.cpp:183`), so `Screen_01` fails too.
- Neither the app nor Help mentions the naming rule.
- **Fix:** show counts per file (e.g. "0 screens · 4 stage · 1 guide"), plus a warning that states the rule and points out near-misses like `Screen…`.

### 2. A missing scene file gets the wrong error, then disappears from settings
Reproduced. If a file can't be found at launch (drive not mounted, file moved):
- The alert says "Unknown File Format — Failed to load FBX file." and doesn't name the file.
- The row disappears, and on quit the path is removed from `settings.json` (`src/Managers/SceneManager.mm:34`, `addFBXSync`). The real ufbx error only goes to `NSLog`.
- **Fix:** keep the row as "Missing — Locate… / Remove", keep the path saved, and use separate messages for "not found" and "couldn't read".

---

## P1: major friction

### 3. The file list hides filenames
Each row shows the full absolute path cut off on the right, so two files from the same folder look identical.
- The list is too short for its rows (`src/Managers/SceneManager.mm:184`): it allows 4 text lines per entry, but the rows with buttons are taller. Even a single file's Reload/Remove buttons are cut off, and you reach them through a 3-point scrollbar.
- **Fix:** show the filename prominently and the folder dimmed (full path on hover), and size the rows to fit.

### 4. The panel covers about 24% of the 3D view
The 3D view fills the whole window, and the 250 pt panel sits on top at 70% opacity.
- With the Front camera, the whole left screen is behind the panel, so you only see the real framing after pressing `C`.
- Bright content shows through the panel text; for example, the video's "26" appeared behind the Source section.
- **Fix:** draw the 3D view only in the area beside an opaque panel (or offer that as a mode).

### 5. Delete Camera can't be undone and doesn't ask
`src/Managers/ViewManager.mm:136`. Removing an FBX takes two clicks, but deleting a camera you set up by hand takes one. That's backwards: an FBX is easy to add back and a deleted camera isn't. Camera moves and `R` (reset) can't be undone either.
- **Fix:** use the same two-click confirm, and add ⌘Z to step back through recent camera views.

### 6. You can't tell when Syphon is waiting for a sender
When the remembered sender isn't running, the menu shows "(No Server)" instead of something like "Waiting for 'App – Server'…" (`src/Sources/SyphonSource.mm:86`). The remembered name (`wantedName_`) is kept but never shown, so users pick the server again because they think the connection was lost.

### 7. Checkboxes and radio buttons are nearly invisible
- An unchecked box measures **1.16:1** against the panel, because the frame colour (`FrameBg`) is at 0.55 opacity (`src/ImGuiApp.mm:35`). WCAG 1.4.11 requires 3:1.
- Disabled text measures 2.1:1 (`DisabledAlpha` 0.25), and "Add Camera" is disabled without saying why.
- The ImGui interface is invisible to VoiceOver.

---

## P2: degraded but recoverable

### 8. Panel layout
- Cameras and Visibility start collapsed.
- Walk mode is under Misc instead of View.
- With both open, the panel runs off the bottom of the window and Misc is cut off.
- Visibility options are sorted alphabetically, not by how often they're used.

### 9. Standard Mac features are missing
There's no File menu (⌘O, Open Recent) or View menu, files can't be dropped on the Dock icon, and the window size isn't remembered. Native menus would also list every shortcut. That fixes discoverability without adding anything to the screen, and gives VoiceOver users the main actions.

### 10. Unclear labels
- "Coord" and "Number: 2" (it means 2 cameras).
- Pos/Rot fields without X/Y/Z or cm/° labels.
- A field-of-view slider from 0 to 180.
- "(No Source)" for video but "(No Image)" for images.
- "Failed to load the image as texture."
- "Enable Screen Blending" with no explanation.
- Help says "Rotate camera" for orbit.

### 11. Help is only a shortcut table
It's in a see-through window (`MiscManager::drawHelp`). It doesn't cover preparing a scene: the naming rules and Cinema 4D export guidance from the original README.

### 12. Shortcuts give no feedback when the panel is hidden
`W`, `G` and `1–9` change things without confirmation, and `G` does nothing visible if the scene has no guides.

---

## P3: polish
- "Show Control" stays on screen in the clean view.
- The video time shows "26F" with no total.
- Cameras beyond 9 have no shortcut keys.
- Full screen is a checkbox when it's really an action.
- Trackpads have no pinch-to-zoom or ⌃-click for right-click.

---

## Heuristic scores (0 = fine, 4 = catastrophic)

| Heuristic | Score | Heuristic | Score |
|---|---|---|---|
| H1 Shows what's happening | 2 | H6 Shows rather than relies on memory | **3** |
| H2 Uses the user's language | 2 | H7 Speed for experts | 1 |
| H3 Undo and escape routes | **3** | H8 Clean, focused design | 2 |
| H4 Consistency | 2 | H9 Error messages and recovery | **3** |
| H5 Prevents errors | **3** | H10 Help | 2 |

## Task walkthroughs

| Task | Result | Where it breaks |
|---|---|---|
| First run: see my content on my stage | **Fail** | Naming rule is never explained; zero screens gives no message (#1) |
| Preview from the FBX's cameras | Friction | "Number: 2" is unclear; the `1–9` keys are only listed in Help |
| Save a custom viewpoint | Friction | Cameras starts collapsed; Add Camera is disabled with no reason given |
| Clean view for a client | Friction | The panel covers the shot; "Show Control" stays on screen |
| Reopen after moving a file or unmounting a drive | **Fail** | Wrong error, and the file is dropped from settings (#2) |
| Scrub to a specific frame | Pass | No total duration shown |

---

## What works (keep it in the redesign)
- Orbiting around whatever is under the cursor (a GPU pick on the real geometry).
- Syphon reconnecting automatically by name.
- Shortcuts ignored while you type, and scrolling over the panel doesn't zoom.
- Files loading in the background, with "Loading…" on their row.
- The two-click Remove with a highlighted confirm.
- The WALK indicator that's always visible in Walk mode.
- The UV test chart as the default texture, which shows orientation instantly.
- The camera-name badge.
- The snapshot harness, which lets the redesign be checked visually.

---

## Suggested order
1. **Quick fixes, no layout changes:** #1, #2, #5, #6, #10, and filenames in the list (#3). These are mostly logic and wording.
2. **Redesign:** the 3D view beside an opaque panel (#4), the panel layout (#8), File and View menus (#9), and contrast (#7). After this, update the smoke test's fixed click positions ([HANDOFF.md §8.4](HANDOFF.md#84-keep-the-tests-in-step-with-the-layout)).
3. **A bigger question:** all settings are one global state. If the app is used to preview several venues, a saved setup per venue (scenes, cameras and source) might be the biggest single improvement.
