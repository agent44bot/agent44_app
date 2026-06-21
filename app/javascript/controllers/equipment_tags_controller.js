import { Controller } from "@hotwired/stimulus"

// Tag picker for a recipe's per-station equipment. The palette (catalogValue)
// is a starter set + everything used on other recipes; selectedValue is what's
// already on this recipe. Tap a palette tag to add it, tap an added tag to
// remove it, type a brand-new item (which joins the palette next time), or tap
// a palette tag's "-" to delete it from the palette for good. Typing in the Add
// box highlights matching palette tags.
//
// The selected list is mirrored into a hidden <textarea name="equipment"> as
// newline-joined text, so the existing server-side parse_equipment is unchanged.
export default class extends Controller {
  static targets = ["selected", "catalog", "input", "field", "paletteLabel"]
  static values = { catalog: Array, selected: Array, hideUrl: String, saveUrl: String }

  connect() {
    this.selected = [...this.selectedValue]
    this.catalog = [...this.catalogValue]
    this.query = ""
    this.render()
  }

  add(event) { this.#addName(event.params.name); this.#persist() }

  remove(event) {
    const name = event.params.name
    this.selected = this.selected.filter(n => n.toLowerCase() !== name.toLowerCase())
    this.render()
    this.#persist()
  }

  addNew(event) {
    event?.preventDefault()
    const name = this.inputTarget.value.trim()
    if (!name) return
    this.#addName(name)
    this.inputTarget.value = ""
    this.query = ""
    this.inputTarget.focus()
    this.render()
    this.#persist()
  }

  // Highlight palette tags that match what's being typed in the Add box.
  filter() {
    this.query = this.inputTarget.value.trim().toLowerCase()
    this.render()
  }

  // Remove a tag from the shared palette permanently (persisted server-side).
  deleteForever(event) {
    event.stopPropagation()
    const name = event.params.name
    if (!window.confirm(`Delete "${name}" from the equipment list for all recipes?`)) return
    fetch(this.hideUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.#csrf() },
      body: JSON.stringify({ name })
    }).then(r => {
      if (!r.ok) return
      const lc = name.toLowerCase()
      const wasSelected = this.selected.some(n => n.toLowerCase() === lc)
      this.catalog = this.catalog.filter(n => n.toLowerCase() !== lc)
      this.selected = this.selected.filter(n => n.toLowerCase() !== lc)
      this.render()
      if (wasSelected) this.#persist()
    }).catch(() => {})
  }

  // Auto-save the recipe's equipment list (called on every add/remove) so the
  // user doesn't have to click "Save & refresh preview" for equipment changes.
  #persist() {
    if (!this.hasSaveUrlValue || !this.saveUrlValue) return
    fetch(this.saveUrlValue, {
      method: "PATCH",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.#csrf() },
      body: JSON.stringify({ equipment: this.selected.join("\n") })
    }).catch(() => {})
  }

  #addName(name) {
    const clean = name.trim()
    if (!clean) return
    const lc = clean.toLowerCase()
    if (!this.selected.some(n => n.toLowerCase() === lc)) this.selected.push(clean)
    if (!this.catalog.some(n => n.toLowerCase() === lc)) this.catalog.push(clean)
    this.render()
  }

  render() {
    this.selectedTarget.innerHTML = this.selected.length
      ? this.selected.map(n => this.#selectedChip(n)).join("")
      : '<span class="text-xs text-gray-600">No equipment added yet.</span>'

    const available = this.catalog
      .filter(n => !this.selected.some(s => s.toLowerCase() === n.toLowerCase()))
      .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()))
    this.catalogTarget.innerHTML = available.map(n => this.#paletteChip(n)).join("")
    if (this.hasPaletteLabelTarget) this.paletteLabelTarget.classList.toggle("hidden", available.length === 0)

    this.fieldTarget.value = this.selected.join("\n")
  }

  #selectedChip(name) {
    const esc = this.#escape(name)
    return `<button type="button" data-action="equipment-tags#remove" data-equipment-tags-name-param="${esc}" title="Remove from this recipe" ` +
      `class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-orange-600/20 text-orange-200 border border-orange-600/40 text-sm cursor-pointer hover:bg-orange-600/30">` +
      `${esc}<span class="text-orange-400 font-bold">&times;</span></button>`
  }

  #paletteChip(name) {
    const esc = this.#escape(name)
    const match = this.query && name.toLowerCase().includes(this.query)
    const dim = this.query && !match
    const look = match
      ? "border-orange-500 bg-orange-600/15 text-white ring-1 ring-orange-500"
      : "border-gray-700 bg-gray-800 text-gray-300 hover:border-orange-500 hover:text-white"
    const opacity = dim ? "opacity-40" : ""
    return `<span class="inline-flex items-center rounded-full border text-sm overflow-hidden ${look} ${opacity}">` +
      `<button type="button" data-action="equipment-tags#add" data-equipment-tags-name-param="${esc}" title="Add" ` +
        `class="inline-flex items-center gap-1 px-2.5 py-1 cursor-pointer"><span class="font-bold opacity-70">+</span>${esc}</button>` +
      `<button type="button" data-action="equipment-tags#deleteForever" data-equipment-tags-name-param="${esc}" title="Delete this tag for all recipes" ` +
        `class="px-2 py-1 cursor-pointer text-gray-500 hover:text-red-400 border-l border-gray-700/70 font-bold">&minus;</button>` +
    `</span>`
  }

  #csrf() {
    const m = document.querySelector('meta[name="csrf-token"]')
    return m ? m.getAttribute("content") : ""
  }

  #escape(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }
}
