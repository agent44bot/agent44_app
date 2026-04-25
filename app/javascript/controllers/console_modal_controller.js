import { Controller } from "@hotwired/stimulus"

// Opens a <dialog> showing captured browser console errors for a smoke
// run. The errors are stored on the trigger element as a data attribute
// so we can keep one shared dialog at the bottom of the table instead of
// rendering a dialog per row.
export default class extends Controller {
  static targets = ["dialog", "body", "title"]

  open(event) {
    const trigger = event.currentTarget
    const errors = trigger.dataset.consoleErrors || ""
    const label = trigger.dataset.consoleLabel || "Browser console"
    this.titleTarget.textContent = label
    this.bodyTarget.textContent = errors
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }
}
