import { Controller } from "@hotwired/stimulus"

// Ingredient rows on the packet editor: add a blank line below any row, or
// nudge a row up or down, so the list can stay in the order the recipe uses
// it. The server saves ingredients in the order the fields appear on the
// page, so moving the DOM node is the whole reorder. An inserted row gets a
// fresh, unique index in its field names so it never collides with an
// existing row.
export default class extends Controller {
  static targets = ["row"]

  insert(event) {
    const row = this.#row(event)
    const copy = row.cloneNode(true)
    const index = `n${Date.now()}${Math.floor(Math.random() * 1000)}`
    copy.querySelectorAll("input").forEach((input) => {
      input.value = ""
      input.name = input.name.replace(/\[ingredients\]\[[^\]]+\]/, `[ingredients][${index}]`)
      input.removeAttribute("id")
    })
    copy.querySelectorAll("[data-ingredient-rows-warning]").forEach((el) => el.remove())
    row.after(copy)
  }

  up(event) {
    const row = this.#row(event)
    const prev = this.rowTargets[this.rowTargets.indexOf(row) - 1]
    if (!prev) return
    prev.before(row)
    this.#changed(row)
  }

  down(event) {
    const row = this.#row(event)
    const next = this.rowTargets[this.rowTargets.indexOf(row) + 1]
    if (!next) return
    next.after(row)
    this.#changed(row)
  }

  #row(event) {
    return this.rowTargets.find((row) => row.contains(event.currentTarget))
  }

  // Let the packet autosave pick up the new order.
  #changed(row) {
    row.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
