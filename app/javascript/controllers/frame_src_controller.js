import { Controller } from "@hotwired/stimulus"

// Swap an embedded turbo-frame's src from a <select> so the handout's
// Pull sheet tab reloads the chosen class date's pull sheet on demand.
export default class extends Controller {
  static targets = ["frame", "link"]

  update(event) {
    const url = event.target.value
    this.frameTarget.src = url
    // Keep the "open to print" link pointing at the selected class. The frame
    // src carries embedded=1; strip it for the standalone (printable) page.
    if (this.hasLinkTarget) {
      this.linkTarget.href = url.replace(/[?&]embedded=1/, "")
    }
  }
}
