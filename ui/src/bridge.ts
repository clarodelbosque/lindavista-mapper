// Bridge to the native app (src/WebPanel.mm). The app pushes the whole panel state as JSON
// whenever it changes; the panel sends small actions back. Outside the app (npm run dev in
// a browser) a local preview state stands in, so the panel can be designed on its own.
import { useCallback, useEffect, useState } from "react"

export type VisibilityKey = "screens" | "stages" | "guides" | "wireframe" | "grid" | "cameras"
export type NavMode = "orbit" | "walk"

export type SceneFile = {
  id: number
  name: string
  folder: string
  size: string
  loading: boolean
  cameras: number
  hasScreens: boolean
}

export type Vector3 = [number, number, number]

export type PanelState = {
  version: string
  panelVisible: boolean
  scene: { files: SceneFile[] }
  // level: 0 = nothing loaded, 1 = waiting (e.g. for a Syphon server), 2 = live
  source: {
    selected: number
    names: string[]
    status: string
    level: 0 | 1 | 2
    flipTexture: boolean
    syphon: { servers: string[]; connectedIndex: number }
    image: { loaded: boolean; name: string }
    video: { loaded: boolean; name: string; playing: boolean; frame: number; totalFrames: number }
  }
  // index: 0 = custom view, N = preset N (1-based, like the 1-9 keys)
  camera: {
    index: number
    presets: string[]
    position: Vector3
    rotation: Vector3
    fov: number
    fixUpDirection: boolean
  }
  navMode: NavMode
  visibility: Record<VisibilityKey, boolean>
  screenBlending: boolean
  // 0.1-1.0; only meaningful (and only shown) while screenBlending is on
  screenBlendOpacity: number
  misc: { windowOnTop: boolean; fullscreen: boolean }
}

export type PanelAction =
  | { type: "ready" }
  | { type: "setVisibility"; key: VisibilityKey; value: boolean }
  | { type: "selectCamera"; index: number }
  | { type: "selectSource"; index: number }
  | { type: "setNavMode"; mode: NavMode }
  | { type: "setPanelVisible"; visible: boolean }
  | { type: "setPanelCollapsed"; collapsed: boolean }
  | { type: "key"; phase: "down" | "up"; key: string; repeat: boolean }
  | { type: "addSceneFile" }
  | { type: "reloadSceneFile"; id: number }
  | { type: "removeSceneFile"; id: number }
  | { type: "importSceneCameras"; id: number }
  | { type: "setCameraPosition"; value: Vector3 }
  | { type: "setCameraRotation"; value: Vector3 }
  | { type: "setCameraFov"; value: number }
  | { type: "setFixUpDirection"; value: boolean }
  | { type: "setScreenBlending"; value: boolean }
  | { type: "setScreenBlendOpacity"; value: number }
  | { type: "addCamera" }
  | { type: "deleteCamera" }
  | { type: "loadImage" }
  | { type: "loadVideo" }
  | { type: "closeVideo" }
  | { type: "toggleVideoPlayback" }
  | { type: "stepVideo"; frames: number }
  | { type: "seekVideo"; frame: number }
  | { type: "selectSyphonServer"; index: number }
  | { type: "setFlipTexture"; value: boolean }
  | { type: "setWindowOnTop"; value: boolean }
  | { type: "toggleFullscreen" }

declare global {
  interface Window {
    webkit?: { messageHandlers?: { vm?: { postMessage(message: unknown): void } } }
    __vmReceive?: (state: PanelState) => void
  }
}

const native = window.webkit?.messageHandlers?.vm
export const isNative = native !== undefined

export function send(action: PanelAction) {
  if (native) native.postMessage(action)
  else preview(action)
}

// Optimistic update, so a control responds before the app's next state push confirms it.
// Continuous controls (drags, sliders, toggles) need this to feel direct; one-shot actions
// that open a native dialog (load/add/import) don't -- the next push arrives within a frame.
function apply(state: PanelState, action: PanelAction): PanelState {
  switch (action.type) {
    case "setVisibility":
      return { ...state, visibility: { ...state.visibility, [action.key]: action.value } }
    case "selectCamera":
      return { ...state, camera: { ...state.camera, index: action.index } }
    case "selectSource":
      return { ...state, source: { ...state.source, selected: action.index } }
    case "setNavMode":
      return { ...state, navMode: action.mode }
    case "setPanelVisible":
      return { ...state, panelVisible: action.visible }
    case "setCameraPosition":
      return { ...state, camera: { ...state.camera, position: action.value, index: 0 } }
    case "setCameraRotation":
      return { ...state, camera: { ...state.camera, rotation: action.value, index: 0 } }
    case "setCameraFov":
      return { ...state, camera: { ...state.camera, fov: action.value, index: 0 } }
    case "setFixUpDirection":
      return { ...state, camera: { ...state.camera, fixUpDirection: action.value } }
    case "setScreenBlending":
      return { ...state, screenBlending: action.value }
    case "setScreenBlendOpacity":
      return { ...state, screenBlendOpacity: action.value }
    case "removeSceneFile":
      return { ...state, scene: { files: state.scene.files.filter((f) => f.id !== action.id) } }
    case "toggleVideoPlayback":
      return { ...state, source: { ...state.source, video: { ...state.source.video, playing: !state.source.video.playing } } }
    case "seekVideo":
      return { ...state, source: { ...state.source, video: { ...state.source.video, frame: action.frame } } }
    case "selectSyphonServer":
      return { ...state, source: { ...state.source, syphon: { ...state.source.syphon, connectedIndex: action.index } } }
    case "setFlipTexture":
      return { ...state, source: { ...state.source, flipTexture: action.value } }
    case "setWindowOnTop":
      return { ...state, misc: { ...state.misc, windowOnTop: action.value } }
    default:
      return state
  }
}

export function usePanelState(): [PanelState | null, (action: PanelAction) => void] {
  const [state, setState] = useState<PanelState | null>(null)
  useEffect(() => {
    window.__vmReceive = setState
    send({ type: "ready" })
    return () => {
      window.__vmReceive = undefined
    }
  }, [])
  const dispatch = useCallback((action: PanelAction) => {
    setState((current) => (current ? apply(current, action) : current))
    send(action)
  }, [])
  return [state, dispatch]
}

// --- Browser preview -------------------------------------------------------------------

let previewState: PanelState = {
  version: "3.1.0",
  panelVisible: true,
  scene: {
    files: [
      { id: 1, name: "main_stage.fbx", folder: "~/Shows/Arena", size: "4.2 MB", loading: false, cameras: 3, hasScreens: true },
      { id: 2, name: "props_left.fbx", folder: "~/Shows/Arena/props", size: "812 KB", loading: false, cameras: 0, hasScreens: false },
    ],
  },
  source: {
    selected: 0,
    names: ["Syphon", "Image", "Video"],
    status: "Waiting for Syphon Sender",
    level: 1,
    flipTexture: false,
    syphon: { servers: ["Resolume - Composition", "TouchDesigner"], connectedIndex: -1 },
    image: { loaded: false, name: "" },
    video: { loaded: false, name: "", playing: false, frame: 0, totalFrames: 0 },
  },
  camera: { index: 1, presets: ["Front of house", "Balcony", "Stage left"], position: [0, 120, 600], rotation: [0, 0, 0], fov: 40, fixUpDirection: true },
  navMode: "walk",
  visibility: { screens: true, stages: true, guides: true, wireframe: false, grid: true, cameras: true },
  screenBlending: false,
  screenBlendOpacity: 1,
  misc: { windowOnTop: false, fullscreen: false },
}

let nextPreviewFileId = 3

function preview(action: PanelAction) {
  if (action.type === "key") {
    if (action.phase !== "down" || action.repeat) return
    const v = previewState.visibility
    if (action.key === "x") action = { type: "setVisibility", key: "wireframe", value: !v.wireframe }
    else if (action.key === "g") action = { type: "setVisibility", key: "guides", value: !v.guides }
    else if (/^[1-9]$/.test(action.key) && Number(action.key) <= previewState.camera.presets.length) action = { type: "selectCamera", index: Number(action.key) }
    else return
  }

  // Actions that open a native file dialog or background load have no real target in the
  // browser preview; simulate a plausible result instead of a no-op.
  switch (action.type) {
    case "addSceneFile": {
      const id = nextPreviewFileId++
      const files = [...previewState.scene.files, { id, name: `stage_${id}.fbx`, folder: "~/Shows/Arena", size: "—", loading: true, cameras: 0, hasScreens: false }]
      previewState = { ...previewState, scene: { files } }
      window.__vmReceive?.(previewState)
      setTimeout(() => {
        previewState = { ...previewState, scene: { files: previewState.scene.files.map((f) => (f.id === id ? { ...f, loading: false, size: "2.1 MB", cameras: 1, hasScreens: true } : f)) } }
        window.__vmReceive?.(previewState)
      }, 600)
      return
    }
    case "reloadSceneFile": {
      previewState = { ...previewState, scene: { files: previewState.scene.files.map((f) => (f.id === action.id ? { ...f, loading: true } : f)) } }
      window.__vmReceive?.(previewState)
      setTimeout(() => {
        previewState = { ...previewState, scene: { files: previewState.scene.files.map((f) => (f.id === action.id ? { ...f, loading: false } : f)) } }
        window.__vmReceive?.(previewState)
      }, 400)
      return
    }
    case "loadImage":
      previewState = { ...previewState, source: { ...previewState.source, image: { loaded: true, name: "test-card.png" } } }
      break
    case "loadVideo":
      previewState = { ...previewState, source: { ...previewState.source, video: { loaded: true, name: "content.mov", playing: true, frame: 0, totalFrames: 300 } } }
      break
    case "closeVideo":
      previewState = { ...previewState, source: { ...previewState.source, video: { loaded: false, name: "", playing: false, frame: 0, totalFrames: 0 } } }
      break
    case "stepVideo":
      previewState = { ...previewState, source: { ...previewState.source, video: { ...previewState.source.video, frame: Math.max(0, previewState.source.video.frame + action.frames) } } }
      break
  }

  if (action.type !== "ready") previewState = apply(previewState, action)
  const state = previewState
  queueMicrotask(() => window.__vmReceive?.(state))
}
