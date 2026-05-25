import { Controller } from "@hotwired/stimulus"

// Opens the printable schedule without triggering the surrounding card
// link (preventDefault stops the ancestor <a> from navigating). The print
// page auto-prints when given ?autoprint=1.
//
// In the native iOS/Android app we navigate in the SAME webview so the
// user stays signed in — a new "_blank" tab launches the external system
// browser, which doesn't share the app's session and forces a re-login.
// On the web we keep opening a new tab so the hub stays put.
export default class extends Controller {
  static values = { url: String }

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    const cap = window.Capacitor
    const nativeApp = !!(cap && (typeof cap.isNativePlatform === "function" ? cap.isNativePlatform() : cap.isNative))
    if (nativeApp) {
      window.location.assign(this.urlValue)
    } else {
      window.open(this.urlValue, "_blank", "noopener")
    }
  }
}
