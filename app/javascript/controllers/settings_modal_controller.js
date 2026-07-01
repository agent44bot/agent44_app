import { Controller } from "@hotwired/stimulus"

// Workspace Settings modal. Opens the settings panel in a native <dialog> so it
// overlays the page instead of pushing the agent cards down. ESC closes it (a
// <dialog> freebie); so does the close button and a backdrop click.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
