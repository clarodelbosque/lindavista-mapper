import type { ComponentType, MouseEvent as ReactMouseEvent, ReactNode } from "react"
import { useEffect, useRef, useState } from "react"
import {
  Box,
  Camera,
  Cast,
  Check,
  Clapperboard,
  Download,
  Footprints,
  Grid3x3,
  Image as ImageIcon,
  Keyboard,
  LoaderCircle,
  Maximize,
  Minimize2,
  MonitorPlay,
  Move3d,
  Orbit,
  PanelLeftClose,
  PanelLeftOpen,
  Pin,
  Play,
  Pause,
  Plus,
  Projector,
  RotateCw,
  Ruler,
  SkipBack,
  SkipForward,
  Spline,
  Trash2,
  TriangleAlert,
  Upload,
  X,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { usePanelState } from "@/bridge"
import type { NavMode, PanelAction, PanelState, SceneFile, Vector3, VisibilityKey } from "@/bridge"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Kbd, KbdGroup } from "@/components/ui/kbd"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Select, SelectContent, SelectItem, SelectSeparator, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Separator } from "@/components/ui/separator"
import { Slider } from "@/components/ui/slider"
import { Switch } from "@/components/ui/switch"
import { Toggle } from "@/components/ui/toggle"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"

type Dispatch = (action: PanelAction) => void
type Icon = ComponentType<{ className?: string }>

export default function App() {
  const [state, dispatch] = usePanelState()
  if (!state) return <div className="h-full border-r bg-background" />

  // The app sets the panel's width (drag its right edge); at the 60pt rail width the
  // collapsed layout takes over. A media query rather than state, so the switch happens in
  // the same layout pass as the resize, with no frame of the wrong layout.
  return (
    <TooltipProvider delayDuration={400}>
      <div className="h-full max-[120px]:hidden">
        <ExpandedPanel state={state} dispatch={dispatch} />
      </div>
      <div className="hidden h-full max-[120px]:block">
        <CollapsedRail state={state} dispatch={dispatch} />
      </div>
    </TooltipProvider>
  )
}

function ExpandedPanel({ state, dispatch }: { state: PanelState; dispatch: Dispatch }) {
  return (
    <aside className="flex h-full flex-col border-r bg-background">
      <PanelHeader onCollapse={() => dispatch({ type: "setPanelCollapsed", collapsed: true })} />
      <ScrollArea className="min-h-0 flex-1">
        <StageSection files={state.scene.files} dispatch={dispatch} />
        <Separator />
        <SourceSection source={state.source} dispatch={dispatch} />
        <Separator />
        <CameraSection camera={state.camera} navMode={state.navMode} dispatch={dispatch} />
        <Separator />
        <DisplaySection
          visibility={state.visibility}
          screenBlending={state.screenBlending}
          screenBlendOpacity={state.screenBlendOpacity}
          dispatch={dispatch}
        />
        <Separator />
        <WindowSection misc={state.misc} dispatch={dispatch} />
      </ScrollArea>
      <PanelFooter version={state.version} />
    </aside>
  )
}

function PanelHeader({ onCollapse }: { onCollapse: () => void }) {
  return (
    <header className="flex h-12 shrink-0 items-center gap-2.5 border-b px-(--panel-gutter)">
      <div className="flex size-6 items-center justify-center rounded-md bg-primary/15 text-primary">
        <Projector className="size-3.5" />
      </div>
      <span className="flex-1 truncate text-sm font-semibold tracking-tight">Linda Vista Mapper</span>
      <Tooltip>
        <TooltipTrigger asChild>
          <Button variant="ghost" size="icon-sm" onClick={onCollapse} aria-label="Collapse panel" data-testid="collapse-panel">
            <PanelLeftClose />
          </Button>
        </TooltipTrigger>
        <TooltipContent side="bottom" align="end">
          Collapse panel
        </TooltipContent>
      </Tooltip>
    </header>
  )
}

function Section({ title, aside, children }: { title: string; aside?: ReactNode; children: ReactNode }) {
  return (
    <section className="px-(--panel-gutter) py-4">
      <div className="mb-3 flex h-5 items-center justify-between">
        <h2 className="text-xs font-medium text-muted-foreground">{title}</h2>
        {aside}
      </div>
      {children}
    </section>
  )
}

// --- Stage -------------------------------------------------------------------------------

function shortFolder(folder: string) {
  const parts = folder.split("/")
  return parts.length > 4 ? `${parts[0]}/…/${parts.slice(-2).join("/")}` : folder
}

function StageSection({ files, dispatch }: { files: SceneFile[]; dispatch: Dispatch }) {
  const anyLoading = files.some((f) => f.loading)
  return (
    <Section
      title="Stage"
      aside={
        <div className="flex items-center gap-2">
          {files.length > 0 && <span className="text-xs text-muted-foreground tabular-nums">{files.length} {files.length === 1 ? "file" : "files"}</span>}
          <Tooltip>
            <TooltipTrigger asChild>
              <Button variant="ghost" size="icon-sm" disabled={anyLoading} onClick={() => dispatch({ type: "addSceneFile" })} aria-label="Add FBX" data-testid="add-scene-file">
                <Plus />
              </Button>
            </TooltipTrigger>
            <TooltipContent side="bottom" align="end">
              Add FBX
            </TooltipContent>
          </Tooltip>
        </div>
      }
    >
      {files.length === 0 ? (
        <button
          type="button"
          onClick={() => dispatch({ type: "addSceneFile" })}
          className="flex w-full flex-col items-center gap-1.5 rounded-lg border border-dashed px-4 py-6 text-center hover:border-ring hover:bg-muted/30"
        >
          <Upload className="mb-1 size-5 text-muted-foreground" />
          <p className="text-sm font-medium">Drop an FBX file, or click to browse</p>
          <p className="text-xs text-muted-foreground">Meshes named “screen…” show your source.</p>
        </button>
      ) : (
        <ul className="flex flex-col gap-2" data-testid="scene-files">
          {files.map((file) => (
            <SceneFileRow key={file.id} file={file} dispatch={dispatch} />
          ))}
        </ul>
      )}
    </Section>
  )
}

function SceneFileRow({ file, dispatch }: { file: SceneFile; dispatch: Dispatch }) {
  const [confirmingRemove, setConfirmingRemove] = useState(false)

  return (
    <li className="flex gap-3 rounded-lg border bg-card/50 p-2.5">
      <div className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-md bg-muted text-muted-foreground">
        <Box className="size-4" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between gap-2">
          <span className="truncate text-sm font-medium">{file.name}</span>
          <span className="shrink-0 text-xs text-muted-foreground tabular-nums">{file.size}</span>
        </div>
        <Tooltip>
          <TooltipTrigger asChild>
            <p className="truncate text-xs text-muted-foreground">{shortFolder(file.folder)}</p>
          </TooltipTrigger>
          <TooltipContent side="bottom" align="start">
            {file.folder}
          </TooltipContent>
        </Tooltip>
        <div className="mt-2 flex flex-wrap items-center gap-1.5">
          {file.loading ? (
            <Badge variant="secondary">
              <LoaderCircle className="animate-spin" /> Loading…
            </Badge>
          ) : (
            <>
              {file.hasScreens ? (
                <Badge variant="secondary">
                  <MonitorPlay /> Screens
                </Badge>
              ) : (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Badge className="bg-amber-400/15 text-amber-300">
                      <TriangleAlert /> No screens
                    </Badge>
                  </TooltipTrigger>
                  <TooltipContent side="bottom" align="start" className="max-w-56">
                    No meshes named “screen…” in this file, so the source won’t appear on it.
                  </TooltipContent>
                </Tooltip>
              )}
              {file.cameras > 0 && (
                <Tooltip>
                  <TooltipTrigger asChild>
                    <button
                      type="button"
                      onClick={() => dispatch({ type: "importSceneCameras", id: file.id })}
                      className="focus-visible:outline-none"
                    >
                      <Badge variant="secondary" className="hover:bg-primary/15 hover:text-primary">
                        <Download /> Import {file.cameras} {file.cameras === 1 ? "camera" : "cameras"}
                      </Badge>
                    </button>
                  </TooltipTrigger>
                  <TooltipContent side="bottom" align="start">
                    Add to the camera preset list
                  </TooltipContent>
                </Tooltip>
              )}
              <span className="ml-auto flex items-center gap-0.5">
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() => dispatch({ type: "reloadSceneFile", id: file.id })}
                      aria-label="Reload"
                    >
                      <RotateCw />
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent side="bottom">Reload</TooltipContent>
                </Tooltip>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() => {
                        if (confirmingRemove) dispatch({ type: "removeSceneFile", id: file.id })
                        else setConfirmingRemove(true)
                      }}
                      onBlur={() => setConfirmingRemove(false)}
                      aria-label={confirmingRemove ? "Confirm remove" : "Remove"}
                      className={cn(confirmingRemove && "text-destructive hover:bg-destructive/10")}
                    >
                      {confirmingRemove ? <Check /> : <Trash2 />}
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent side="bottom">{confirmingRemove ? "Click to confirm" : "Remove"}</TooltipContent>
                </Tooltip>
              </span>
            </>
          )}
        </div>
      </div>
    </li>
  )
}

// --- Source ------------------------------------------------------------------------------

const SOURCE_ICONS: Record<string, Icon> = { Syphon: Cast, Image: ImageIcon, Video: Clapperboard }

function SourceSection({ source, dispatch }: { source: PanelState["source"]; dispatch: Dispatch }) {
  return (
    <Section title="Source">
      <ToggleGroup
        type="single"
        variant="outline"
        spacing={0}
        className="w-full"
        value={String(source.selected)}
        onValueChange={(value) => value && dispatch({ type: "selectSource", index: Number(value) })}
      >
        {source.names.map((name, index) => {
          const SourceIcon = SOURCE_ICONS[name] ?? Cast
          return (
            <ToggleGroupItem
              key={name}
              value={String(index)}
              className="min-w-0 flex-1 shrink data-[state=on]:bg-primary/15 data-[state=on]:text-primary"
              data-testid={`source-${name.toLowerCase()}`}
            >
              <SourceIcon /> <span className="truncate">{name}</span>
            </ToggleGroupItem>
          )
        })}
      </ToggleGroup>
      <div className="mt-3 flex min-w-0 items-center gap-2 rounded-md bg-muted/50 px-2.5 py-2" data-testid="source-status">
        <StatusDot level={source.level} />
        <span className="min-w-0 truncate text-xs text-muted-foreground" title={source.status}>
          {source.status}
        </span>
      </div>

      {source.names[source.selected] === "Syphon" && <SyphonControls syphon={source.syphon} dispatch={dispatch} />}
      {source.names[source.selected] === "Image" && <ImageControls image={source.image} dispatch={dispatch} />}
      {source.names[source.selected] === "Video" && <VideoControls video={source.video} dispatch={dispatch} />}

      <label className="mt-3 flex h-8 items-center gap-2.5 rounded-md px-2 -mx-2 hover:bg-muted/50">
        <span className="flex-1 text-sm text-muted-foreground">Flip texture vertically</span>
        <Switch
          size="sm"
          checked={source.flipTexture}
          onCheckedChange={(value) => dispatch({ type: "setFlipTexture", value })}
          data-testid="flip-texture"
        />
      </label>
    </Section>
  )
}

function SyphonControls({ syphon, dispatch }: { syphon: PanelState["source"]["syphon"]; dispatch: Dispatch }) {
  return (
    <Select
      value={syphon.connectedIndex >= 0 ? String(syphon.connectedIndex) : undefined}
      onValueChange={(value) => dispatch({ type: "selectSyphonServer", index: Number(value) })}
    >
      <SelectTrigger className="mt-3 w-full" data-testid="syphon-server">
        <SelectValue placeholder={syphon.servers.length === 0 ? "(No Server)" : "(Select Server)"} />
      </SelectTrigger>
      <SelectContent position="popper">
        {syphon.servers.map((name, i) => (
          <SelectItem key={i} value={String(i)}>
            <Cast /> {name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

function ImageControls({ image, dispatch }: { image: PanelState["source"]["image"]; dispatch: Dispatch }) {
  return (
    <div className="mt-3 flex items-center gap-2">
      <Button variant="outline" size="sm" onClick={() => dispatch({ type: "loadImage" })} data-testid="load-image">
        <ImageIcon /> Load Image
      </Button>
      <span className="min-w-0 flex-1 truncate text-xs text-muted-foreground">{image.loaded ? image.name : "(No Image)"}</span>
    </div>
  )
}

function VideoControls({ video, dispatch }: { video: PanelState["source"]["video"]; dispatch: Dispatch }) {
  return (
    <div className="mt-3 flex flex-col gap-2.5">
      <div className="flex items-center gap-2">
        <Button variant="outline" size="sm" onClick={() => dispatch({ type: "loadVideo" })} data-testid="load-video">
          <Clapperboard /> Load Video
        </Button>
        <span className="min-w-0 flex-1 truncate text-xs text-muted-foreground">{video.loaded ? video.name : "(No Source)"}</span>
        {video.loaded && (
          <Tooltip>
            <TooltipTrigger asChild>
              <Button variant="ghost" size="icon-sm" onClick={() => dispatch({ type: "closeVideo" })} aria-label="Close video" data-testid="close-video">
                <X />
              </Button>
            </TooltipTrigger>
            <TooltipContent side="bottom">Close</TooltipContent>
          </Tooltip>
        )}
      </div>
      {video.loaded && (
        <div className="flex items-center gap-1.5">
          <Button variant="ghost" size="icon-sm" onClick={() => dispatch({ type: "stepVideo", frames: -1 })} aria-label="Previous frame">
            <SkipBack />
          </Button>
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={() => dispatch({ type: "toggleVideoPlayback" })}
            aria-label={video.playing ? "Pause" : "Play"}
            data-testid="video-playback"
          >
            {video.playing ? <Pause /> : <Play />}
          </Button>
          <Button variant="ghost" size="icon-sm" onClick={() => dispatch({ type: "stepVideo", frames: 1 })} aria-label="Next frame">
            <SkipForward />
          </Button>
          <Slider
            className="mx-1 flex-1"
            min={0}
            max={Math.max(0, video.totalFrames - 1)}
            step={1}
            value={[video.frame]}
            onValueChange={([frame]) => dispatch({ type: "seekVideo", frame })}
            data-testid="video-seek"
          />
          <span className="w-10 shrink-0 text-right text-xs text-muted-foreground tabular-nums">{video.frame}F</span>
        </div>
      )}
    </div>
  )
}

function StatusDot({ level, className }: { level: PanelState["source"]["level"]; className?: string }) {
  return (
    <span
      className={cn(
        "size-2 shrink-0 rounded-full",
        level === 2 && "bg-emerald-400",
        level === 1 && "animate-pulse bg-amber-400",
        level === 0 && "bg-muted-foreground/40",
        className,
      )}
    />
  )
}

// --- Camera ------------------------------------------------------------------------------

// A single coordinate. Keeps its own text while focused, so a partial edit (e.g. typing
// "-" before the digits) isn't stomped by the next state push from the app; it resyncs
// from `value` on blur and whenever an unfocused field's value changes underneath it.
// Click-and-drag to scrub the value (1 unit per pixel, matching the ImGui DragFloat3
// this replaces), or click once (with no drag) to focus and type an exact number.
const DRAG_THRESHOLD_PX = 3

function NumberField({ value, onChange }: { value: number; onChange: (value: number) => void }) {
  const [text, setText] = useState(value.toFixed(1))
  const focused = useRef(false)
  const inputRef = useRef<HTMLInputElement>(null)
  const drag = useRef<{ startX: number; startValue: number; dragging: boolean } | null>(null)

  useEffect(() => {
    if (!focused.current) setText(value.toFixed(1))
  }, [value])

  const handleMouseDown = (e: ReactMouseEvent<HTMLInputElement>) => {
    if (focused.current) return // already editing text -- let the click place/select the caret normally
    drag.current = { startX: e.clientX, startValue: value, dragging: false }

    const onMove = (move: MouseEvent) => {
      const state = drag.current
      if (!state) return
      const dx = move.clientX - state.startX
      if (!state.dragging) {
        if (Math.abs(dx) < DRAG_THRESHOLD_PX) return
        state.dragging = true
        inputRef.current?.blur()
        document.body.style.cursor = "ew-resize"
      }
      onChange(Math.round((state.startValue + dx) * 10) / 10)
    }
    const onUp = () => {
      drag.current = null
      document.body.style.cursor = ""
      window.removeEventListener("mousemove", onMove)
      window.removeEventListener("mouseup", onUp)
    }
    window.addEventListener("mousemove", onMove)
    window.addEventListener("mouseup", onUp)
  }

  return (
    <Input
      ref={inputRef}
      type="text"
      inputMode="decimal"
      value={text}
      onMouseDown={handleMouseDown}
      onFocus={() => (focused.current = true)}
      onBlur={() => {
        focused.current = false
        setText(value.toFixed(1))
      }}
      onChange={(e) => {
        setText(e.target.value)
        const n = parseFloat(e.target.value)
        if (Number.isFinite(n)) onChange(n)
      }}
      className="h-7 cursor-ew-resize px-1.5 text-center text-xs tabular-nums focus:cursor-text"
    />
  )
}

// A single typed number with a unit suffix ("40.0°", "51%"), for values that also have a
// slider. Shows the suffix when idle and the bare number while editing; the value is
// committed (clamped to min..max) on Enter or blur, and Escape abandons the edit. Unlike
// NumberField it doesn't scrub: the slider beside it already covers dragging.
// Limits of the FOV and screen-blending opacity controls. Keep in step with kMinFovDegrees /
// kMaxFovDegrees / kMinBlendOpacity in src/Managers/ViewManager.mm, which clamp again.
const FOV_MIN = 1
const FOV_MAX = 140
const OPACITY_MIN_PERCENT = 10
const OPACITY_MAX_PERCENT = 100

function UnitInput({
  value,
  min,
  max,
  decimals,
  unit,
  onCommit,
  label,
  testId,
}: {
  value: number
  min: number
  max: number
  decimals: number
  unit: string
  onCommit: (value: number) => void
  label: string
  testId?: string
}) {
  const [editing, setEditing] = useState(false)
  const [text, setText] = useState("")
  const abandoned = useRef(false)
  const display = `${value.toFixed(decimals)}${unit}`

  const finish = () => {
    setEditing(false)
    if (abandoned.current) {
      abandoned.current = false
      return
    }
    const n = parseFloat(text)
    if (!Number.isFinite(n)) return // not a number: the field just shows the current value again
    onCommit(Number(Math.min(max, Math.max(min, n)).toFixed(decimals)))
  }

  return (
    <Input
      type="text"
      inputMode="decimal"
      aria-label={label}
      value={editing ? text : display}
      onFocus={(e) => {
        setText(value.toFixed(decimals))
        setEditing(true)
        e.currentTarget.select()
      }}
      onBlur={finish}
      onChange={(e) => setText(e.target.value)}
      onKeyDown={(e) => {
        if (e.key === "Enter") e.currentTarget.blur()
        else if (e.key === "Escape") {
          abandoned.current = true
          e.currentTarget.blur()
        }
      }}
      className="h-7 w-16 shrink-0 px-1.5 text-center text-xs tabular-nums"
      data-testid={testId}
    />
  )
}

function Vector3Field({ label, value, onChange }: { label: string; value: Vector3; onChange: (value: Vector3) => void }) {
  return (
    <div className="mt-3 flex items-center gap-3">
      <span className="w-20 shrink-0 text-sm text-muted-foreground">{label}</span>
      <div className="grid flex-1 grid-cols-3 gap-1.5">
        {value.map((axisValue, i) => (
          <NumberField
            key={i}
            value={axisValue}
            onChange={(n) => {
              const next = [...value] as Vector3
              next[i] = n
              onChange(next)
            }}
          />
        ))}
      </div>
    </div>
  )
}

function CameraSection({ camera, navMode, dispatch }: { camera: PanelState["camera"]; navMode: NavMode; dispatch: Dispatch }) {
  return (
    <Section
      title="Camera"
      aside={
        <span className="flex items-center gap-0.5">
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant="ghost"
                size="icon-sm"
                disabled={camera.index !== 0}
                onClick={() => dispatch({ type: "addCamera" })}
                aria-label="Add camera from current view"
                data-testid="add-camera"
              >
                <Plus />
              </Button>
            </TooltipTrigger>
            <TooltipContent side="bottom" align="end">
              Save current view as a preset
            </TooltipContent>
          </Tooltip>
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant="ghost"
                size="icon-sm"
                disabled={camera.index === 0}
                onClick={() => dispatch({ type: "deleteCamera" })}
                aria-label="Delete selected camera"
                data-testid="delete-camera"
              >
                <Trash2 />
              </Button>
            </TooltipTrigger>
            <TooltipContent side="bottom" align="end">
              Delete preset
            </TooltipContent>
          </Tooltip>
        </span>
      }
    >
      <Select value={String(camera.index)} onValueChange={(value) => dispatch({ type: "selectCamera", index: Number(value) })}>
        <SelectTrigger className="w-full" data-testid="camera-select">
          <SelectValue />
        </SelectTrigger>
        <SelectContent position="popper">
          <SelectItem value="0">
            <Move3d /> Custom view
          </SelectItem>
          {camera.presets.length > 0 && <SelectSeparator />}
          {camera.presets.map((name, i) => (
            <SelectItem key={i} value={String(i + 1)} data-testid={`camera-${i + 1}`}>
              <Camera /> {name}
              {i < 9 && <Kbd className="ml-1">{i + 1}</Kbd>}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Vector3Field label="Position" value={camera.position} onChange={(value) => dispatch({ type: "setCameraPosition", value })} />
      <Vector3Field label="Rotation" value={camera.rotation} onChange={(value) => dispatch({ type: "setCameraRotation", value })} />

      <div className="mt-3 flex items-center gap-3">
        <span className="w-20 shrink-0 text-sm text-muted-foreground">FOV</span>
        <Slider
          className="flex-1"
          min={FOV_MIN}
          max={FOV_MAX}
          step={0.5}
          value={[Math.min(FOV_MAX, camera.fov)]}
          onValueChange={([value]) => dispatch({ type: "setCameraFov", value })}
          data-testid="camera-fov"
        />
        <UnitInput
          value={camera.fov}
          min={FOV_MIN}
          max={FOV_MAX}
          decimals={1}
          unit="°"
          label="Field of view in degrees"
          onCommit={(value) => dispatch({ type: "setCameraFov", value })}
          testId="camera-fov-input"
        />
      </div>

      <label className="mt-2.5 flex h-7 items-center gap-2.5 rounded-md px-2 -mx-2 hover:bg-muted/50">
        <span className="flex-1 text-sm text-muted-foreground">Fix up direction</span>
        <Switch
          size="sm"
          checked={camera.fixUpDirection}
          onCheckedChange={(value) => dispatch({ type: "setFixUpDirection", value })}
          data-testid="fix-up-direction"
        />
      </label>

      <div className="mt-3 flex items-center justify-between">
        <span className="text-sm text-muted-foreground">Navigation</span>
        <ToggleGroup
          type="single"
          variant="outline"
          size="sm"
          spacing={0}
          value={navMode}
          onValueChange={(value) => value && dispatch({ type: "setNavMode", mode: value as NavMode })}
        >
          <ToggleGroupItem value="orbit" className="data-[state=on]:bg-primary/15 data-[state=on]:text-primary" data-testid="nav-orbit">
            <Orbit /> Orbit
          </ToggleGroupItem>
          <ToggleGroupItem value="walk" className="data-[state=on]:bg-primary/15 data-[state=on]:text-primary" data-testid="nav-walk">
            <Footprints /> Walk
          </ToggleGroupItem>
        </ToggleGroup>
      </div>
      {navMode === "walk" ? (
        <div className="mt-2.5 flex flex-col gap-1.5 text-xs text-muted-foreground">
          <span className="flex items-center gap-1.5">
            <KbdGroup>
              <Kbd>W</Kbd>
              <Kbd>A</Kbd>
              <Kbd>S</Kbd>
              <Kbd>D</Kbd>
            </KbdGroup>
            move
            <KbdGroup className="ml-1.5">
              <Kbd>Q</Kbd>
              <Kbd>E</Kbd>
            </KbdGroup>
            down / up
          </span>
          <span>Right-drag to look around</span>
        </div>
      ) : (
        <p className="mt-2.5 text-xs text-muted-foreground">Drag to orbit, right-drag to dolly, scroll to zoom</p>
      )}
    </Section>
  )
}

// --- Display -----------------------------------------------------------------------------

const LAYERS: { key: VisibilityKey; label: string; icon: Icon }[] = [
  { key: "screens", label: "Screens", icon: MonitorPlay },
  { key: "stages", label: "Stage geometry", icon: Box },
  { key: "guides", label: "Guides", icon: Ruler },
  { key: "wireframe", label: "Wireframe", icon: Spline },
  { key: "grid", label: "Floor grid", icon: Grid3x3 },
  { key: "cameras", label: "Camera markers", icon: Camera },
]

const LAYER_KEYS: Partial<Record<VisibilityKey, string>> = { guides: "G", wireframe: "X" }

function DisplaySection({
  visibility,
  screenBlending,
  screenBlendOpacity,
  dispatch,
}: {
  visibility: PanelState["visibility"]
  screenBlending: boolean
  screenBlendOpacity: number
  dispatch: Dispatch
}) {
  return (
    <Section title="Display">
      <ul className="-mx-2 flex flex-col">
        {LAYERS.map(({ key, label, icon: LayerIcon }) => (
          <li key={key}>
            <label className="flex h-8 items-center gap-2.5 rounded-md px-2 hover:bg-muted/50">
              <LayerIcon className="size-4 text-muted-foreground" />
              <span className="flex-1 text-sm">{label}</span>
              {LAYER_KEYS[key] && <Kbd>{LAYER_KEYS[key]}</Kbd>}
              <Switch
                checked={visibility[key]}
                onCheckedChange={(value) => dispatch({ type: "setVisibility", key, value })}
                data-testid={`vis-${key}`}
              />
            </label>
          </li>
        ))}
      </ul>
      <Separator className="my-3" />
      <label className="flex h-8 items-center gap-2.5 rounded-md px-2 -mx-2 hover:bg-muted/50">
        <span className="flex-1 text-sm">Screen blending</span>
        <Switch
          checked={screenBlending}
          onCheckedChange={(value) => dispatch({ type: "setScreenBlending", value })}
          data-testid="screen-blending"
        />
      </label>
      {screenBlending && (
        <div className="mt-2 flex items-center gap-3">
          <span className="w-20 shrink-0 text-sm text-muted-foreground">Opacity</span>
          <Slider
            className="flex-1"
            min={OPACITY_MIN_PERCENT}
            max={OPACITY_MAX_PERCENT}
            step={1}
            value={[Math.round(screenBlendOpacity * 100)]}
            onValueChange={([percent]) => dispatch({ type: "setScreenBlendOpacity", value: percent / 100 })}
            data-testid="screen-blend-opacity"
          />
          <UnitInput
            value={Math.round(screenBlendOpacity * 100)}
            min={OPACITY_MIN_PERCENT}
            max={OPACITY_MAX_PERCENT}
            decimals={0}
            unit="%"
            label="Screen blending opacity in percent"
            onCommit={(percent) => dispatch({ type: "setScreenBlendOpacity", value: percent / 100 })}
            testId="screen-blend-opacity-input"
          />
        </div>
      )}
    </Section>
  )
}

// --- Window --------------------------------------------------------------------------

function WindowSection({ misc, dispatch }: { misc: PanelState["misc"]; dispatch: Dispatch }) {
  return (
    <Section title="Window">
      <ul className="-mx-2 flex flex-col">
        <li>
          <label className="flex h-8 items-center gap-2.5 rounded-md px-2 hover:bg-muted/50">
            <Pin className="size-4 text-muted-foreground" />
            <span className="flex-1 text-sm">Always on top</span>
            <Switch
              checked={misc.windowOnTop}
              onCheckedChange={(value) => dispatch({ type: "setWindowOnTop", value })}
              data-testid="window-on-top"
            />
          </label>
        </li>
        <li>
          <button
            type="button"
            onClick={() => dispatch({ type: "toggleFullscreen" })}
            className="flex h-8 w-full items-center gap-2.5 rounded-md px-2 text-left hover:bg-muted/50"
            data-testid="toggle-fullscreen"
          >
            {misc.fullscreen ? <Minimize2 className="size-4 text-muted-foreground" /> : <Maximize className="size-4 text-muted-foreground" />}
            <span className="flex-1 text-sm">{misc.fullscreen ? "Exit full screen" : "Enter full screen"}</span>
            <Kbd>F</Kbd>
          </button>
        </li>
      </ul>
    </Section>
  )
}

// --- Footer ------------------------------------------------------------------------------

const SHORTCUTS: [string, string][] = [
  ["X", "Wireframe"],
  ["G", "Guides"],
  ["R", "Reset camera"],
  ["1–9", "Camera presets"],
  ["F", "Full screen"],
  ["C", "Hide panel"],
  ["Space", "Play / pause video"],
  ["← →", "Step video frames"],
]

function PanelFooter({ version }: { version: string }) {
  return (
    <footer className="flex h-10 shrink-0 items-center justify-between border-t px-(--panel-gutter) text-xs text-muted-foreground">
      <span>v{version}</span>
      <Tooltip>
        <TooltipTrigger asChild>
          <Button variant="ghost" size="icon-sm" aria-label="Keyboard shortcuts">
            <Keyboard />
          </Button>
        </TooltipTrigger>
        <TooltipContent side="top" align="end" className="block">
          <dl className="grid grid-cols-[auto_1fr] items-center gap-x-3 gap-y-1.5 py-1">
            {SHORTCUTS.map(([keys, action]) => (
              <div key={keys} className="contents">
                <dt>
                  <Kbd>{keys}</Kbd>
                </dt>
                <dd>{action}</dd>
              </div>
            ))}
          </dl>
        </TooltipContent>
      </Tooltip>
    </footer>
  )
}

// --- Collapsed rail ----------------------------------------------------------------------
// 60pt wide: 28px buttons inside the 16px gutters. Labels use native `title` tooltips,
// which (unlike in-page tooltips) can extend past the narrow web view.

function RailButton({ title, onClick, children, testId }: { title: string; onClick: () => void; children: ReactNode; testId?: string }) {
  return (
    <Button variant="ghost" size="icon-sm" className="relative size-[28px]" title={title} aria-label={title} onClick={onClick} data-testid={testId}>
      {children}
    </Button>
  )
}

function RailCount({ children, warn }: { children: ReactNode; warn?: boolean }) {
  return (
    <span
      className={cn(
        "absolute -top-1 -right-1 flex h-3.5 min-w-3.5 items-center justify-center rounded-full px-0.5 text-[9px] leading-none font-semibold tabular-nums",
        warn ? "bg-amber-400 text-black" : "bg-muted text-foreground",
      )}
    >
      {children}
    </span>
  )
}

function CollapsedRail({ state, dispatch }: { state: PanelState; dispatch: Dispatch }) {
  const expand = () => dispatch({ type: "setPanelCollapsed", collapsed: false })
  const { files } = state.scene
  const missingScreens = files.some((file) => !file.loading && !file.hasScreens)
  const sourceName = state.source.names[state.source.selected] ?? ""
  const SourceIcon = SOURCE_ICONS[sourceName] ?? Cast
  const { camera } = state
  const cameraName = camera.index > 0 ? camera.presets[camera.index - 1] : "Custom view"

  return (
    <nav className="flex h-full flex-col items-center border-r bg-background" data-testid="panel-rail">
      <div className="flex h-12 w-full shrink-0 items-center justify-center border-b">
        <RailButton title="Expand panel" onClick={expand} testId="expand-panel">
          <PanelLeftOpen />
        </RailButton>
      </div>

      <div className="flex flex-col items-center gap-2 py-3">
        <RailButton title={`Stage: ${files.length} ${files.length === 1 ? "file" : "files"}${missingScreens ? ", one without screens" : ""}`} onClick={expand}>
          <Box />
          {files.length > 0 && <RailCount warn={missingScreens}>{files.length}</RailCount>}
        </RailButton>
        <RailButton title={`Source: ${sourceName}, ${state.source.status}`} onClick={expand}>
          <SourceIcon />
          <StatusDot level={state.source.level} className="absolute -top-0.5 -right-0.5 size-1.5" />
        </RailButton>
        <RailButton title={`Camera: ${cameraName}`} onClick={expand}>
          <Camera />
          {camera.index > 0 && <RailCount>{camera.index}</RailCount>}
        </RailButton>
      </div>

      <Separator className="w-7!" />

      <div className="flex flex-col items-center gap-1 py-3">
        {LAYERS.map(({ key, label, icon: LayerIcon }) => (
          <Toggle
            key={key}
            size="sm"
            pressed={state.visibility[key]}
            onPressedChange={(value) => dispatch({ type: "setVisibility", key, value })}
            title={LAYER_KEYS[key] ? `${label} (${LAYER_KEYS[key]})` : label}
            aria-label={label}
            className="size-[28px] min-w-0 px-0 text-muted-foreground/60 data-[state=on]:bg-primary/15 data-[state=on]:text-primary"
            data-testid={`rail-vis-${key}`}
          >
            <LayerIcon />
          </Toggle>
        ))}
      </div>

      <div className="mt-auto flex h-10 w-full shrink-0 items-center justify-center border-t">
        <span
          className="flex size-[28px] items-center justify-center rounded-md text-muted-foreground"
          title={SHORTCUTS.map(([keys, action]) => `${keys}  ${action}`).join("\n")}
          aria-label="Keyboard shortcuts"
        >
          <Keyboard className="size-4" />
        </span>
      </div>
    </nav>
  )
}
