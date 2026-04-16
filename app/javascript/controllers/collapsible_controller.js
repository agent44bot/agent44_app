import { Controller } from "@hotwired/stimulus"

// Collapsible section. Clicking the header toggles the body's visibility
// and rotates the icon. Count in the header stays visible in both states.
export default class extends Controller {
  static targets = ["body", "icon"]

  toggle() {
    const collapsed = this.bodyTarget.classList.toggle("hidden")
    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle("-rotate-90", collapsed)
    }
  }
}
