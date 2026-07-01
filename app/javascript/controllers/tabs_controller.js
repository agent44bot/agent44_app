import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = {
    activeClasses: { type: String, default: "text-orange-600 border-orange-600 bg-orange-50/50" },
    inactiveClasses: { type: String, default: "text-gray-500 border-transparent" }
  }

  connect() {
    // Ensure first tab is active on initial load — fixes iOS Safari
    // not connecting controllers when page is opened from iMessage/external links.
    // If ?tab=<name|index> is in the URL, honor it so links like
    // /nykitchen?tab=tests deep-link into a specific tab.
    const initial = this.#initialIndex()
    this.#activate(initial)
    this.#scrollToHash()
  }

  // Deep-link support: if the URL has a #hash pointing at an element inside the
  // now-active tab (e.g. a social engagement push -> #post-123), scroll it into
  // view and briefly highlight it. The browser can't do this itself because the
  // target lived in a hidden panel until #activate ran just above.
  #scrollToHash() {
    const hash = window.location.hash
    if (!hash || hash.length < 2) return
    let el
    try { el = this.element.querySelector(hash) } catch (_) { return }
    if (!el) return
    requestAnimationFrame(() => {
      el.scrollIntoView({ behavior: "smooth", block: "center" })
      el.classList.add("bg-orange-500/10", "ring-1", "ring-orange-500/40")
      setTimeout(() => el.classList.remove("bg-orange-500/10", "ring-1", "ring-orange-500/40"), 2600)
    })
  }

  #initialIndex() {
    const param = new URLSearchParams(window.location.search).get("tab")
    if (!param) return 0
    const byName = this.tabTargets.findIndex(t => t.dataset.tabName === param.toLowerCase())
    if (byName !== -1) return byName
    const asIndex = parseInt(param, 10)
    if (!Number.isNaN(asIndex) && asIndex >= 0 && asIndex < this.tabTargets.length) return asIndex
    return 0
  }

  #activate(index) {
    const active = this.activeClassesValue.split(" ")
    const inactive = this.inactiveClassesValue.split(" ")
    this.tabTargets.forEach((tab, i) => {
      if (i === index) {
        tab.classList.add(...active)
        tab.classList.remove(...inactive)
      } else {
        tab.classList.remove(...active)
        tab.classList.add(...inactive)
      }
    })
    this.panelTargets.forEach((panel, i) => {
      panel.classList.toggle("hidden", i !== index)
    })
    this.element.querySelectorAll("[data-tabs-chrome-for]").forEach(el => {
      const indices = el.dataset.tabsChromeFor.split(" ").map(s => s.trim())
      el.classList.toggle("hidden", !indices.includes(String(index)))
    })
  }

  select(event) {
    const index = parseInt(event.currentTarget.dataset.tabIndex)
    this.#activate(index)
  }
}
