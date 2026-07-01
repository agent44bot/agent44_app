import { Controller } from "@hotwired/stimulus"

// Field Roster on the NY Kitchen hub. A few agents (Sam, Neon, Echo) show by
// default; the rest start hidden and appear as chips in a "Hidden cards" tray.
// Clicking a chip reveals that card. Reveals persist per-browser via
// localStorage so a card the user opened stays open on their next visit.
export default class extends Controller {
  static targets = ["card", "chip", "tray"]
  static values = { storageKey: { type: String, default: "nyk-roster-revealed" } }

  connect() {
    this.#revealed().forEach(key => this.#show(key))
    this.#syncTray()
  }

  reveal(event) {
    const key = event.currentTarget.dataset.key
    this.#show(key)
    const set = new Set(this.#revealed())
    set.add(key)
    try { localStorage.setItem(this.storageKeyValue, JSON.stringify([...set])) } catch (_) {}
    this.#syncTray()
  }

  #show(key) {
    // Cards hide via .ra-card.is-hidden (beats the inline .ra-card display:flex);
    // chips/tray hide via Tailwind's .hidden.
    this.cardTargets.filter(c => c.dataset.key === key).forEach(c => c.classList.remove("is-hidden"))
    this.chipTargets.filter(c => c.dataset.key === key).forEach(c => c.classList.add("hidden"))
  }

  // Hide the whole tray once every chip has been revealed.
  #syncTray() {
    if (!this.hasTrayTarget) return
    const allShown = this.chipTargets.every(c => c.classList.contains("hidden"))
    this.trayTarget.classList.toggle("hidden", allShown)
  }

  #revealed() {
    try { return JSON.parse(localStorage.getItem(this.storageKeyValue)) || [] } catch (_) { return [] }
  }
}
