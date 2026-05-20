import { Controller } from "@hotwired/stimulus"

// Toggles the compose form below the Social Agent header. Separate from the
// admin-settings `collapsible` controller so the kabab and "New post" buttons
// can sit side-by-side in the header without sharing state.
export default class extends Controller {
  static targets = ["body"]

  toggle() {
    const collapsed = this.bodyTarget.classList.toggle("hidden")
    if (!collapsed) {
      this.bodyTarget.scrollIntoView({ behavior: "smooth", block: "start" })
    }
  }
}
