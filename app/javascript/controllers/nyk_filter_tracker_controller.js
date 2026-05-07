import { Controller } from "@hotwired/stimulus"

// Pings the server when the user expands the NYK Filter card so we can
// auto-hide the card after 14 days of no engagement.
export default class extends Controller {
  static values = { url: String }

  track() {
    if (!this.urlValue) return
    fetch(this.urlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: { "X-Requested-With": "XMLHttpRequest" }
    }).catch(() => {})
  }
}
