import { Controller } from "@hotwired/stimulus"

// Opens the printable schedule in a new window without triggering the
// surrounding card link (preventDefault stops the ancestor <a> from
// navigating). The page auto-prints when given ?autoprint=1.
//
// We deliberately open a new window even in the native app: iOS only shows
// a print dialog in Safari, not in the in-app WKWebView, so this hands the
// URL to Safari. The print page is public (no login wall) so that works
// without re-authenticating.
export default class extends Controller {
  static values = { url: String }

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    window.open(this.urlValue, "_blank", "noopener")
  }
}
