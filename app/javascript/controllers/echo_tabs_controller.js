import { Controller } from "@hotwired/stimulus"

// Echo page tabs: Listen / New post / Post history. Client-side show/hide of the
// three panels; remembers the last tab per user in localStorage. `select` is
// wired to the tab buttons; `show` lets other buttons (e.g. the header "New
// post") jump to a tab via data-show-tab.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { storageKey: String, default: { type: String, default: "listen" } }

  connect() {
    const saved = this.storageKeyValue ? window.localStorage.getItem(this.storageKeyValue) : null
    this.activate(this.hasPanel(saved) ? saved : this.defaultValue)
  }

  select(event) { this.go(event.currentTarget.dataset.tab) }
  show(event)   { this.go(event.currentTarget.dataset.showTab) }

  go(name) {
    if (!this.hasPanel(name)) return
    this.activate(name)
    if (this.storageKeyValue) window.localStorage.setItem(this.storageKeyValue, name)
  }

  activate(name) {
    this.panelTargets.forEach((p) => p.classList.toggle("hidden", p.dataset.tab !== name))
    this.tabTargets.forEach((t) => {
      const on = t.dataset.tab === name
      t.classList.toggle("border-orange-500", on)
      t.classList.toggle("text-white", on)
      t.classList.toggle("border-transparent", !on)
      t.classList.toggle("text-gray-400", !on)
      t.setAttribute("aria-selected", on ? "true" : "false")
    })
  }

  hasPanel(name) {
    return !!name && this.panelTargets.some((p) => p.dataset.tab === name)
  }
}
