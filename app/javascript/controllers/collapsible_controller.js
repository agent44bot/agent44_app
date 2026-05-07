import { Controller } from "@hotwired/stimulus"

// Collapsible section. Clicking the header toggles the body's visibility
// and rotates the icon. Count in the header stays visible in both states.
//
// `mobileCollapsed` collapses only on viewports narrower than the Tailwind
// `sm` breakpoint (640px). Desktop stays expanded.
export default class extends Controller {
  static targets = ["body", "icon"]
  static values = {
    collapsed:       { type: Boolean, default: false },
    mobileCollapsed: { type: Boolean, default: false }
  }

  connect() {
    const isMobile = window.matchMedia("(max-width: 639px)").matches
    if (this.collapsedValue || (this.mobileCollapsedValue && isMobile)) {
      this.bodyTarget.classList.add("hidden")
      if (this.hasIconTarget) this.iconTarget.classList.add("-rotate-90")
    }
  }

  toggle() {
    const collapsed = this.bodyTarget.classList.toggle("hidden")
    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle("-rotate-90", collapsed)
    }
  }
}
