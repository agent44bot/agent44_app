import { Controller } from "@hotwired/stimulus"

// Reloads the packet edit page every few seconds while it is still building, so
// a user who lands on it directly sees the recipe appear without a manual
// refresh. The navbar bar is the primary progress UI; this is just a fallback.
export default class extends Controller {
  connect() {
    this.timer = setTimeout(() => window.location.reload(), 4000)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
