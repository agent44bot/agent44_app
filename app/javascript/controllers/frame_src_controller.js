import { Controller } from "@hotwired/stimulus"

// Drives the handout Pull sheet tab's embedded #grocery_list frame.
//
// The frame ships with no src so nothing loads (no paid aggregation) until the
// tab is opened. Opening the tab calls reload(): the first open sets the src;
// later opens re-fetch so the sheet always reflects the latest equipment (which
// auto-saves without a page reload) and any saved recipe edit. A reload is
// cache-cheap unless the recipe's ingredients actually changed.
export default class extends Controller {
  static targets = ["frame", "select", "link"]

  // Fired by the Pull sheet tab button each time it's clicked.
  reload() {
    if (!this.hasFrameTarget) return
    if (this.frameTarget.getAttribute("src")) {
      this.frameTarget.reload()          // already loaded once -> re-fetch
    } else {
      this.frameTarget.src = this.#url() // first open -> load
    }
  }

  // Fired when the shared-recipe date dropdown changes.
  update(event) {
    if (!this.hasFrameTarget) return
    this.frameTarget.src = event.target.value
    if (this.hasLinkTarget) {
      // Standalone print page is the same URL without the embedded flag.
      this.linkTarget.href = event.target.value.replace(/[?&]embedded=1/, "")
    }
  }

  #url() {
    return this.hasSelectTarget ? this.selectTarget.value : this.frameTarget.dataset.defaultSrc
  }
}
