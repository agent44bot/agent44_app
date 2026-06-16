import { Controller } from "@hotwired/stimulus"

// Collapsible section. Clicking the header toggles the body's visibility
// and rotates the icon. Count in the header stays visible in both states.
//
// `mobileCollapsed` collapses only on viewports narrower than the Tailwind
// `sm` breakpoint (640px). Desktop stays expanded.
//
// `persistKey` (opt-in): remember the open/closed state in localStorage under
// that key, so it survives navigating away and back (e.g. expand a week on
// Sam's list, open Draft Post, come back — the week is still open). When a
// stored state exists it overrides the collapsed / mobileCollapsed defaults.
export default class extends Controller {
  static targets = ["body", "icon"]
  static values = {
    collapsed:       { type: Boolean, default: false },
    mobileCollapsed: { type: Boolean, default: false },
    persistKey:      { type: String,  default: "" },
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

    const stored = this.#readStored()
    let collapse
    if (stored !== null) {
      collapse = stored // a remembered choice wins over the defaults
    } else {
      const isMobile = window.matchMedia("(max-width: 639px)").matches
      collapse = this.collapsedValue || (this.mobileCollapsedValue && isMobile)
    }
    this.#apply(collapse)
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
    this.#writeStored(collapsed)
  }

  #apply(collapse) {
    this.bodyTarget.classList.toggle("hidden", collapse)
    if (this.hasIconTarget) this.iconTarget.classList.toggle("-rotate-90", collapse)
  }

  // localStorage: "1" = collapsed, "0" = expanded. null = nothing stored.
  // Wrapped so private mode / disabled storage degrades to default behavior.
  #readStored() {
    if (!this.persistKeyValue) return null
    try {
      const v = window.localStorage.getItem("collapsible:" + this.persistKeyValue)
      return v === null ? null : v === "1"
    } catch (e) {
      return null
    }
  }

  #writeStored(collapsed) {
    if (!this.persistKeyValue) return
    try {
      window.localStorage.setItem("collapsible:" + this.persistKeyValue, collapsed ? "1" : "0")
    } catch (e) {
      // ignore
    }
  }
}
