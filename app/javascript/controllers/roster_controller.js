import { Controller } from "@hotwired/stimulus"

// Field Roster on the NY Kitchen hub. Sam, Neon, and Echo always show; the rest
// (Iris, Scout, Argus, Carson, Cellar) are controlled by toggle chips in a tray.
// A chip shows its card when on and hides it when off; the eye icon reflects the
// state. Choices persist per-browser via localStorage.
export default class extends Controller {
  static targets = ["card", "chip"]
  static values = { storageKey: { type: String, default: "nyk-roster-revealed" } }

  connect() {
    const revealed = new Set(this.#revealed())
    this.chipTargets.forEach(chip => this.#apply(chip.dataset.key, revealed.has(chip.dataset.key)))
  }

  toggle(event) {
    const key = event.currentTarget.dataset.key
    const set = new Set(this.#revealed())
    const shown = !set.has(key)
    if (shown) set.add(key)
    else set.delete(key)
    this.#apply(key, shown)
    try { localStorage.setItem(this.storageKeyValue, JSON.stringify([...set])) } catch (_) {}
  }

  // Cards hide via .ra-card.is-hidden (beats the inline .ra-card display:flex).
  // The chip's .chip-on class swaps the eye icon + brightens it.
  #apply(key, shown) {
    this.cardTargets.filter(c => c.dataset.key === key).forEach(c => c.classList.toggle("is-hidden", !shown))
    this.chipTargets.filter(c => c.dataset.key === key).forEach(c => {
      c.classList.toggle("chip-on", shown)
      c.setAttribute("aria-pressed", shown ? "true" : "false")
      c.title = `${shown ? "Hide" : "Show"} ${c.dataset.label || "card"}`
    })
  }

  #revealed() {
    try { return JSON.parse(localStorage.getItem(this.storageKeyValue)) || [] } catch (_) { return [] }
  }
}
