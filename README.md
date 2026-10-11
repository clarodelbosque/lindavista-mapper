# Linda Vista Mapper

A native Apple Silicon (arm64) macOS app for previewing projection mapping and non-flat screens. Load a stage model (FBX), pick a video source, and the source is textured onto the model's screen surfaces, so you can see your content in 3D while you create it in another app.

Ale Segura redesigned Linda Vista Mapper, including new features and UI. It is a rebuild of [Virtual Mapper](https://github.com/baku89/VirtualMapper) by Baku Hashimoto (2.3.1), which was Intel-only. See [Credits](#credits-and-license).

## Features

- **Stage models:** load one or more FBX files into the same scene; reload or remove each independently. Import the cameras stored in the FBX as presets.
- **Sources:** **Syphon** (live frames from After Effects, Resolume, VDMX, TouchDesigner and others), **Image** (PNG, JPEG, TIFF, PSD, HEIC, EXR, anything ImageIO reads) and **Video** (H.264, HEVC, ProRes, anything AVFoundation plays; looped, with seek and frame stepping).
- **Navigation:** **Walk** mode by default (WASD + QE to fly, right-drag to look), or switch to **Orbit** to orbit, dolly and pan around the point under the cursor.
- **Camera presets:** save views, switch with the `1`–`9` keys, edit position, rotation, and FOV (1–140°) numerically.
- **Screen blending:** blend the screens over the stage, with an adjustable opacity from 10% to 100%.
- **Layers:** show or hide screens, stage geometry, guides, wireframe, floor grid and camera markers.
- **Native Metal rendering** at Retina resolution, with a React + shadcn/ui control panel beside the 3D view (and the original ImGui sidebar available with `--classic-ui`).

## Preparing a scene

- A mesh whose **node name starts with `screen`** displays the current source. It needs UVs. The match is **case-sensitive**: `screen_left` works, `Screen_01` does not.
- A mesh whose name starts with **`guide`** is a guide; toggle guides with `G`.
- Everything else is stage geometry, lit by a headlight at the camera.
- Perspective cameras in the FBX can be imported as presets; orthographic cameras are skipped.
- The scene is normalized to Y-up centimeters. Materials: diffuse, emissive, ambient and specular colors are used; textures, animation and lights are ignored.

## Keyboard shortcuts

| Key | Action |
|---|---|
| `1`–`9` | Switch to camera preset N |
| `R` | Reset the camera |
| `X` | Toggle wireframe |
| `G` | Toggle guides |
| `C` | Show or hide the control panel |
| `F` | Toggle full screen |
| `Space` | Play or pause video (hold and drag to pan) |
| `←` `→` | Step video one frame |
| `H` (held) | Pan modifier for left-drag |
| `W` `A` `S` `D` `Q` `E` | Fly, in Walk mode |

## Building

Requirements: an Apple Silicon Mac, macOS 12 or later, the **Xcode Command Line Tools** (full Xcode is not needed), and **Node.js with npm** (the control panel is built with Vite as part of `make`).

```sh
make          # builds the web panel, then "build/Linda Vista Mapper.app"
make run      # build and open
make test     # unit tests: FBX loading, camera math, GPU picking
make smoke    # end-to-end checks against the real app (classic UI; opens its window briefly)
make clean    # delete build/
```

The app is ad-hoc signed and not notarized. On another Mac, right-click → **Open** the first time, or run `xattr -dr com.apple.quarantine "Linda Vista Mapper.app"`.

Settings are stored in `~/Library/Application Support/Linda Vista Mapper/settings.json`.

## Documentation

- [`HANDOFF.md`](HANDOFF.md): architecture, UI and controls inventory, settings schema, testing toolkit, known limitations. Start here if you are working on the code.

## Credits and license

Released under the MIT License (see [`LICENSE`](LICENSE)). The behavior and design come from Virtual Mapper 2.3.1, © 2015 HASHIMOTO Baku, also MIT. The icon, test chart, and new features come from Linda Vista Mapper 3.1.0, redesigned by Ale Segura.

Third-party components, with their licenses in `vendor/`: [Dear ImGui](https://github.com/ocornut/imgui) (MIT), [ufbx](https://github.com/ufbx/ufbx) (MIT or public domain), [Syphon-Framework](https://github.com/Syphon/Syphon-Framework) (BSD 2-clause), the Karla font (SIL OFL 1.1). The control panel uses React, Radix UI, Tailwind CSS, shadcn/ui, and lucide-react (see `ui/package.json`).
