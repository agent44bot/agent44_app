import { Controller } from "@hotwired/stimulus"

// Reveals a camera/photo file input only where opening the camera is safe:
// mobile Safari / desktop (the browser owns the permission), or a native build
// carrying the Agent44Cam user-agent token (which means NSCameraUsageDescription
// is present). In an older native app the input stays hidden — invoking the
// camera there crashes iOS. Fail-safe: default is hidden, so no JS == no camera.
export default class extends Controller {
  static targets = ["field", "note"]

  connect() {
    const isNative = !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform())
    const ok = !isNative || navigator.userAgent.includes("Agent44Cam")
    if (!ok) return
    this.fieldTargets.forEach(el => el.classList.remove("hidden"))
    this.noteTargets.forEach(el => el.classList.add("hidden"))
  }
}
