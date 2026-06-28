import { Controller } from "@hotwired/stimulus"

// Full-screen "Generating recipe with AI..." overlay shown the moment a class's
// Add link is clicked. Opening a no-recipe class drafts the recipe server-side
// (Opus, several seconds) before redirecting to the editor, so without this the
// page just sits there with no feedback. The overlay covers that wait and is
// torn down automatically when the editor page loads (this controller's element
// no longer exists there). We also re-hide it on connect / before Turbo caches
// the page so a restored back-button snapshot never shows a stuck spinner.
export default class extends Controller {
  static targets = ["overlay"]

  connect() {
    this.hide()
    this.beforeCache = () => this.hide()
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  show() {
    if (this.hasOverlayTarget) this.overlayTarget.classList.remove("hidden")
  }

  hide() {
    if (this.hasOverlayTarget) this.overlayTarget.classList.add("hidden")
  }
}
