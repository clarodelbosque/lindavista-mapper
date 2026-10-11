#!/usr/bin/env python3
"""End-to-end smoke test for the built app (run with `make smoke`).

Launches Linda Vista Mapper several times with test settings (a window appears briefly each
time), renders each scenario to build/smoke/*.png and checks pixels that prove the
texture orientation of every source and that mouse navigation moves the camera.
"""
import json
import os
import struct
import subprocess
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
OUT = os.path.join(BUILD, "smoke")
APP = os.path.join(BUILD, "Linda Vista Mapper.app", "Contents", "MacOS", "LindaVistaMapper")
FRONT = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 120, 600, 1]
TOP = [0, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 900, 0, 1]

failures = []


class Image:
    def __init__(self, path):
        data = open(path, "rb").read()
        pos, idat = 8, b""
        while pos < len(data):
            length, kind = struct.unpack(">I4s", data[pos:pos + 8])
            body = data[pos + 8:pos + 8 + length]
            pos += 12 + length
            if kind == b"IHDR":
                self.w, self.h, _, color_type = struct.unpack(">IIBB", body[:10])
            elif kind == b"IDAT":
                idat += body
        self.bpp = {2: 3, 6: 4}[color_type]
        self.rows = self._unfilter(zlib.decompress(idat))

    def _unfilter(self, raw):
        stride, bpp = self.w * self.bpp, self.bpp
        rows, prev, i = [], bytearray(stride), 0
        for _ in range(self.h):
            kind, line = raw[i], bytearray(raw[i + 1:i + 1 + stride])
            i += 1 + stride
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                if kind == 1:
                    line[x] = (line[x] + a) & 255
                elif kind == 2:
                    line[x] = (line[x] + b) & 255
                elif kind == 3:
                    line[x] = (line[x] + (a + b) // 2) & 255
                elif kind == 4:
                    pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                    line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
            rows.append(line)
            prev = line
        return rows

    def at(self, fx, fy):
        x, y = int(fx * self.w), int(fy * self.h)
        p = self.rows[y][x * self.bpp:x * self.bpp + 3]
        return tuple(p)


def expect(name, ok, detail):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  ({detail})"))
    if not ok:
        failures.append(name)


def base_settings(selected):
    return {
        "showControl": True,
        "scene": {"isGuiOpened": True, "fbxPaths": [os.path.join(OUT, "scene.fbx")]},
        "view": {
            "isGuiOpened": True,
            "camera": {
                "index": 1,
                "fixUpDirection": True,
                "current": {"matrix": FRONT, "fov": 40},
                "list": [{"name": "Front", "matrix": FRONT, "fov": 40}, {"name": "Top", "matrix": TOP, "fov": 60}],
            },
        },
        "sources": {
            "isGuiOpened": True,
            "selected": selected,
            "image": {"path": os.path.join(ROOT, "resources", "data", "default_tex.png")},
            "syphon": {"inputName": "syphon_test_sender - Test Pattern"},
            "video": {"path": os.path.join(OUT, "movie.mov"), "timeDisplayMode": 1},
        },
    }


def render(name, settings, frames, script=None):
    settings_path = os.path.join(OUT, name + ".json")
    png = os.path.join(OUT, name + ".png")
    json.dump(settings, open(settings_path, "w"), indent=1)
    # Pinned to the classic ImGui sidebar: every fixed coordinate below (drags, clicks,
    # pixel-sample fractions) is calibrated for its layout, not the web panel's.
    cmd = [APP, "--classic-ui", "--settings", settings_path, "--snapshot", png, "--snapshot-frames", str(frames)]
    if script:
        script_path = os.path.join(OUT, name + ".input")
        open(script_path, "w").write("\n".join(script) + "\n")
        cmd += ["--input-script", script_path]
    subprocess.run(cmd, check=True, timeout=60, capture_output=True)
    return Image(png), json.load(open(settings_path))


def is_red(p): return p[0] > 150 and p[1] < 90 and p[2] < 90
def is_blue(p): return p[2] > 150 and p[0] < 90
def is_green(p): return p[1] > 150 and p[0] < 100 and p[2] < 130
def is_pink(p): return p[0] > 150 and p[1] < 110
def is_navy(p): return p[2] > 90 and p[0] < 90 and p[1] < 90


def has_walk_label(img):
    # The "WALK" indicator (ViewManager::drawCameraLabels) sits bottom-right, 10pt margin,
    # drawn white-at-~75%-alpha (HANDOFF 6.4) -- at this font size its glyphs are only a
    # pixel or two of stroke, so this scans every pixel of that corner (a small, cheap
    # region) for anti-aliased ink, rather than sampling single points like the solid-color
    # chart checks above, which could land between strokes and miss it entirely.
    for y in range(int(img.h * 0.95), img.h):
        for x in range(int(img.w * 0.95), img.w):
            if sum(img.at(x / img.w, y / img.h)) > 300:
                return True
    return False


def main():
    os.makedirs(OUT, exist_ok=True)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "make_test_scene.py"), os.path.join(OUT, "scene.fbx")], check=True)
    subprocess.run([os.path.join(BUILD, "make_test_movie"), os.path.join(OUT, "movie.mov"), "90", "30"], check=True, capture_output=True)

    # The center screen spans roughly x 0.29-0.71, y 0.35-0.65 through the Front camera.
    img, _ = render("image", base_settings(1), 30)
    expect("image: top-left of the UV chart is at the top", is_pink(img.at(0.33, 0.37)), img.at(0.33, 0.37))
    expect("image: UV (0,0) is at the bottom-left", is_navy(img.at(0.33, 0.63)), img.at(0.33, 0.63))

    sender = subprocess.Popen([os.path.join(BUILD, "syphon_test_sender"), "20"], stdout=subprocess.DEVNULL)
    try:
        img, _ = render("syphon", base_settings(0), 150)
    finally:
        sender.terminate()
    expect("syphon: red band on top", is_red(img.at(0.55, 0.38)), img.at(0.55, 0.38))
    expect("syphon: blue band at the bottom", is_blue(img.at(0.55, 0.62)), img.at(0.55, 0.62))
    expect("syphon: green stripe on the left", is_green(img.at(0.305, 0.5)), img.at(0.305, 0.5))

    img, _ = render("video", base_settings(2), 60)
    expect("video: red band on top", is_red(img.at(0.55, 0.38)), img.at(0.55, 0.38))
    expect("video: blue band at the bottom", is_blue(img.at(0.55, 0.62)), img.at(0.55, 0.62))
    expect("video: green stripe on the left", is_green(img.at(0.305, 0.5)), img.at(0.305, 0.5))

    # Dragging right orbits the camera to the left of the stage; the result is saved on quit.
    drag = ["10 move 520 380", "12 down left 520 380"]
    drag += [f"{12 + i} drag left {520 + 20 * i} 380" for i in range(1, 11)] + ["23 up left 720 380", "30 key x"]
    _, saved = render("orbit", base_settings(1), 45, drag)
    camera = saved["view"]["camera"]
    expect("orbit: camera left the Front preset", camera["index"] == 0, camera["index"])
    expect("orbit: camera moved to the left", camera["current"]["matrix"][12] < -100, camera["current"]["matrix"][12:15])
    expect("keys: X turned the wireframe on", saved["view"]["visibility"]["wireframe"], saved["view"]["visibility"])

    # Dragging over the control panel must not move the camera.
    panel = ["10 move 150 700", "12 down left 150 700"] + [f"{12 + i} drag left {150 + 7 * i} 700" for i in range(1, 11)]
    _, saved = render("panel_drag", base_settings(1), 40, panel + ["23 up left 220 700"])
    expect("ui: dragging over the panel keeps the camera", saved["view"]["camera"]["index"] == 1, saved["view"]["camera"]["index"])

    # Scene "Remove" requires a second confirming click before it actually removes a file.
    # Two duplicate entries keep the first row's Reload/Remove buttons on-screen without
    # needing to scroll the (fixed-height) file list.
    remove_settings = base_settings(1)
    remove_settings["scene"]["fbxPaths"] = [os.path.join(OUT, "scene.fbx")] * 2
    first_click = ["4 move 105 191", "6 down left 105 191", "8 up left 105 191"]
    _, saved = render("scene_remove_first_click", remove_settings, 20, first_click)
    expect("scene: a single Remove click does not remove the entry",
           len(saved["scene"]["fbxPaths"]) == 2, saved["scene"]["fbxPaths"])

    second_click = first_click + ["12 down left 105 191", "14 up left 105 191"]
    _, saved = render("scene_remove_second_click", remove_settings, 20, second_click)
    expect("scene: a second Remove click removes the entry",
           len(saved["scene"]["fbxPaths"]) == 1, saved["scene"]["fbxPaths"])

    # Clicking Reload in between cancels the pending confirmation: a third Remove click
    # only re-arms "Confirm Remove?", it does not remove the entry.
    reload_then_click = first_click + ["10 move 40 191", "12 down left 40 191", "14 up left 40 191",
                                        "18 move 105 191", "20 down left 105 191", "22 up left 105 191"]
    _, saved = render("scene_remove_cancelled_by_reload", remove_settings, 30, reload_then_click)
    expect("scene: clicking Reload clears a pending Remove confirmation",
           len(saved["scene"]["fbxPaths"]) == 2, saved["scene"]["fbxPaths"])

    # The WALK indicator (bottom-right) must be absent here -- a plain, undragged Orbit-mode
    # render, kept separate from the "orbit" test above since that one drags the camera and
    # turns wireframe on, which can put actual grid-line pixels in the corner this scans and
    # would make it a false positive for this check.
    img, _ = render("orbit_no_walk_label", base_settings(1), 30)
    expect("walk: the WALK indicator is absent in Orbit mode", not has_walk_label(img), "found label pixels")

    # Walk mode: holding W moves the camera forward continuously. W has no wireframe
    # meaning in either nav mode now (X is the only wireframe-toggle key) -- this just
    # guards against a regression reintroducing that old dual meaning.
    walk_settings = base_settings(1)
    walk_settings["view"]["navMode"] = "walk"
    img, saved = render("walk_forward", walk_settings, 90, ["5 keydown w", "80 keyup w"])
    expect("walk: navMode round-trips through settings", saved["view"].get("navMode") == "walk", saved["view"].get("navMode"))
    expect("walk: holding W moves the camera forward", saved["view"]["camera"]["current"]["matrix"][14] < 550,
           saved["view"]["camera"]["current"]["matrix"][12:15])
    expect("walk: W does not toggle wireframe while walking", not saved["view"]["visibility"]["wireframe"], saved["view"]["visibility"])
    expect("walk: the WALK indicator is drawn while navMode is Walk", has_walk_label(img), "no label pixels")

    # The WALK indicator is the fix for a real failure mode: hiding the Control panel (C
    # key) -- common during a live show -- must not hide it too, unlike the existing
    # camera-name badge and seek bar, which HANDOFF 6.3 notes *are* gated on showControl_.
    # It must keep drawing because ViewManager::drawCameraLabels runs on the always-on
    # background draw list (VMApp::frame, step 5), not through an ImGui window of its own.
    img, _ = render("walk_hidden_control", walk_settings, 30, ["5 key c"])
    expect("walk: the WALK indicator still renders with the Control panel hidden", has_walk_label(img), "no label pixels")

    # X is the sole wireframe-toggle key, in both nav modes.
    _, saved = render("walk_x_wireframe", walk_settings, 20, ["5 key x"])
    expect("keys: X turns the wireframe on, even while walking", saved["view"]["visibility"]["wireframe"], saved["view"]["visibility"])

    # Walk mode: right-drag looks around in place (rotates only) instead of Orbit's dolly.
    look_settings = base_settings(1)
    look_settings["view"]["navMode"] = "walk"
    look = ["10 move 520 380", "12 down right 520 380"]
    look += [f"{12 + i} drag right {520 + 20 * i} 380" for i in range(1, 6)] + ["18 up right 620 380"]
    _, saved = render("walk_look", look_settings, 30, look)
    camera = saved["view"]["camera"]
    pos = camera["current"]["matrix"][12:15]
    expect("walk: right-drag look leaves the Front preset (camera rotated)", camera["index"] == 0, camera["index"])
    expect("walk: right-drag look does not move the camera (no dolly)",
           abs(pos[0]) < 1 and abs(pos[1] - 120) < 1 and abs(pos[2] - 600) < 1, pos)

    print(f"\nsnapshots in {OUT}")
    if failures:
        print(f"{len(failures)} check(s) failed")
        sys.exit(1)
    print("all smoke checks passed")


if __name__ == "__main__":
    main()
