import { Controller } from "@hotwired/stimulus"

// On the native iOS/Android app, open EXTERNAL links (e.g. class pages on
// nykitchen.com) in an in-app browser (SFSafariViewController via the Capacitor
// Browser plugin) instead of handing off to standalone Safari. The hand-off is
// slow (the OS backgrounds our app and cold-launches Safari); an in-app browser
// opens instantly and keeps you in the app with a Done button.
//
// On the plain web this does nothing, links behave normally (new tab, etc.).
// Attached once on <body>, so it covers every external link app-wide.
export default class extends Controller {
  connect() {
    if (!this.#isNative()) return
    this.onClick = this.onClick.bind(this)
    this.element.addEventListener("click", this.onClick, true)
  }

  disconnect() {
    if (this.onClick) this.element.removeEventListener("click", this.onClick, true)
  }

  onClick(event) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey) return
    const anchor = event.target.closest && event.target.closest("a[href]")
    if (!anchor) return

    const href = anchor.getAttribute("href") || ""
    if (!/^https?:\/\//i.test(href)) return // in-app paths, tel:, mailto: etc.

    let external
    try {
      external = new URL(href, window.location.href).origin !== window.location.origin
    } catch (_) {
      return
    }
    if (!external) return // same-origin: let the app navigate normally

    const Browser = window.Capacitor.Plugins && window.Capacitor.Plugins.Browser
    if (!Browser) return // plugin unavailable: fall back to default behavior

    event.preventDefault()
    Browser.open({ url: href }).catch(() => {})
  }

  #isNative() {
    return !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform())
  }
}
