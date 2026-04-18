import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "video"]

  open(event) {
    const src = event.params.src
    if (src) {
      this.videoTarget.src = src
    }
    this.dialogTarget.showModal()
  }

  close() {
    this.videoTarget.pause()
    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }
}
