// While the panel has keyboard focus, the app's single-key shortcuts (X, G, 1-9, C, F,
// WASD/QE walking, Space, arrow keys...) would stop at the web view. Forward them to the app
// unless the panel needs the key itself: typing in a field, an open menu, Tab, or Space/
// Enter/arrows on a control that was reached with the keyboard.
import { send } from "@/bridge"

const OWN_WHEN_FOCUSED = new Set([" ", "Enter", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"])

function appKeyName(event: KeyboardEvent): string | null {
  if (event.key === " ") return "space"
  if (event.key === "ArrowLeft") return "left"
  if (event.key === "ArrowRight") return "right"
  const key = event.key.toLowerCase()
  return /^[a-z0-9]$/.test(key) ? key : null
}

function panelWantsKey(event: KeyboardEvent): boolean {
  if (event.metaKey || event.ctrlKey || event.altKey || event.key === "Tab") return true
  const el = document.activeElement as HTMLElement | null
  if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)) return true
  if (document.querySelector("[data-radix-popper-content-wrapper], [role=listbox]")) return true
  const keyboardFocused = el !== null && el !== document.body && el.matches(":focus-visible")
  return keyboardFocused && OWN_WHEN_FOCUSED.has(event.key)
}

export function installKeyForwarding() {
  // Keys whose keydown went to the app, so their keyup does too (held Walk keys, Space-pan).
  const forwarded = new Set<string>()

  document.addEventListener(
    "keydown",
    (event) => {
      const key = appKeyName(event)
      if (!key || panelWantsKey(event)) return
      event.preventDefault()
      forwarded.add(key)
      send({ type: "key", phase: "down", key, repeat: event.repeat })
    },
    true,
  )
  document.addEventListener(
    "keyup",
    (event) => {
      const key = appKeyName(event)
      if (!key || !forwarded.delete(key)) return
      event.preventDefault()
      send({ type: "key", phase: "up", key, repeat: false })
    },
    true,
  )
  // Native-app feel: no browser context menu or text selection in the panel.
  document.addEventListener("contextmenu", (event) => event.preventDefault())
}
