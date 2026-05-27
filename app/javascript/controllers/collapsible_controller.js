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
    mobileCollapsed: { type: Boolean, default: false },
    // Opt-in: when expanding, scroll the body into view. For toggles
    // whose trigger lives far from the body (kebab top-right, body
    // below the fold) so mobile users don't have to scroll to find
    // what they just opened.
    scrollOnExpand:  { type: Boolean, default: false }
  }

  connect() {
    // The body target can be conditionally rendered (e.g. the hub's team
    // section only exists for workspace members), so tolerate its absence
    // instead of throwing "Missing target element 'body'".
    if (!this.hasBodyTarget) return
    const isMobile = window.matchMedia("(max-width: 639px)").matches
    if (this.collapsedValue || (this.mobileCollapsedValue && isMobile)) {
      this.bodyTarget.classList.add("hidden")
      if (this.hasIconTarget) this.iconTarget.classList.add("-rotate-90")
    }
  }

  toggle() {
    if (!this.hasBodyTarget) return
    const collapsed = this.bodyTarget.classList.toggle("hidden")
    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle("-rotate-90", collapsed)
    }
    if (!collapsed && this.scrollOnExpandValue) {
      this.bodyTarget.scrollIntoView({ behavior: "smooth", block: "start" })
    }
  }
}
