import { Controller } from "@hotwired/stimulus"

// Tag picker for a recipe's per-station equipment. The palette (catalogValue)
// is a starter set + everything used on other recipes; selectedValue is what's
// already on this recipe. Tap a palette tag to add it, tap an added tag to
// remove it, or type a brand-new item (which also joins the palette next time).
//
// The selected list is mirrored into a hidden <textarea name="equipment"> as
// newline-joined text, so the existing server-side parse_equipment is unchanged.
export default class extends Controller {
  static targets = ["selected", "catalog", "input", "field", "paletteLabel"]
  static values = { catalog: Array, selected: Array }

  connect() {
    this.selected = [...this.selectedValue]
    this.render()
  }

  add(event) {
    this.#addName(event.params.name)
  }

  remove(event) {
    const name = event.params.name
    this.selected = this.selected.filter(n => n.toLowerCase() !== name.toLowerCase())
    this.render()
  }

  addNew(event) {
    event?.preventDefault()
    const name = this.inputTarget.value.trim()
    if (!name) return
    this.#addName(name)
    this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  #addName(name) {
    const clean = name.trim()
    if (!clean) return
    if (!this.selected.some(n => n.toLowerCase() === clean.toLowerCase())) {
      this.selected.push(clean)
    }
    this.render()
  }

  render() {
    this.selectedTarget.innerHTML = this.selected.length
      ? this.selected.map(n => this.#chip(n, "remove")).join("")
      : '<span class="text-xs text-gray-600">No equipment added yet.</span>'

    const available = this.catalogValue.filter(
      n => !this.selected.some(s => s.toLowerCase() === n.toLowerCase())
    )
    this.catalogTarget.innerHTML = available.map(n => this.#chip(n, "add")).join("")
    if (this.hasPaletteLabelTarget) {
      this.paletteLabelTarget.classList.toggle("hidden", available.length === 0)
    }

    this.fieldTarget.value = this.selected.join("\n")
  }

  #chip(name, action) {
    const esc = this.#escape(name)
    if (action === "remove") {
      return `<button type="button" data-action="equipment-tags#remove" data-equipment-tags-name-param="${esc}" title="Remove" ` +
        `class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-orange-600/20 text-orange-200 border border-orange-600/40 text-sm cursor-pointer hover:bg-orange-600/30">` +
        `${esc}<span class="text-orange-400 font-bold">&times;</span></button>`
    }
    return `<button type="button" data-action="equipment-tags#add" data-equipment-tags-name-param="${esc}" title="Add" ` +
      `class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-gray-800 text-gray-300 border border-gray-700 text-sm cursor-pointer hover:border-orange-500 hover:text-white">` +
      `<span class="text-gray-500 font-bold">+</span>${esc}</button>`
  }

  #escape(s) {
    return String(s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }
}
