import { Controller } from "@hotwired/stimulus"

// Editable pull sheet. The white sheet's quantities, items, section names,
// and the "to taste" line are contenteditable; lines and sections can be
// added or removed. About a second after the last change the whole sheet is
// serialized from the DOM and PATCHed to the server (PullSheetEdit), so the
// print, PDF, and spreadsheet all follow. Leaving the page flushes a pending
// save with a keepalive request; an edit during a save is saved again after.
export default class extends Controller {
  static targets = ["categories", "status", "toTaste", "itemTemplate", "categoryTemplate"]
  static values = { url: String, eventUrl: String, baseKey: String, delay: { type: Number, default: 900 } }

  connect() {
    this.dirty = false
    this.flush = this.flush.bind(this)
    window.addEventListener("pagehide", this.flush)
    document.addEventListener("turbo:before-visit", this.flush)
  }

  disconnect() {
    clearTimeout(this.timer)
    window.removeEventListener("pagehide", this.flush)
    document.removeEventListener("turbo:before-visit", this.flush)
  }

  changed() {
    this.dirty = true
    clearTimeout(this.timer)
    this.#status("Unsaved changes…", "text-gray-500")
    this.timer = setTimeout(() => this.save(), this.delayValue)
  }

  addItem(event) {
    const section = event.currentTarget.closest("[data-category]")
    const list = section.querySelector("[data-items]")
    const li = this.itemTemplateTarget.content.firstElementChild.cloneNode(true)
    list.appendChild(li)
    li.querySelector('[data-field="quantity"]').focus()
    this.changed()
  }

  removeItem(event) {
    event.currentTarget.closest("[data-item]").remove()
    this.changed()
  }

  addCategory() {
    const section = this.categoryTemplateTarget.content.firstElementChild.cloneNode(true)
    this.categoriesTarget.appendChild(section)
    const name = section.querySelector('[data-field="name"]')
    name.focus()
    document.getSelection()?.selectAllChildren(name)
    this.changed()
  }

  removeCategory(event) {
    const section = event.currentTarget.closest("[data-category]")
    const count = section.querySelectorAll("[data-item]").length
    if (count > 0 && !window.confirm(`Remove this section and its ${count} line${count === 1 ? "" : "s"}?`)) return
    section.remove()
    this.changed()
  }

  flush() {
    if (!this.dirty) return
    clearTimeout(this.timer)
    this.dirty = false
    fetch(this.urlValue, { method: "PATCH", body: this.#payload(), headers: this.#headers(), credentials: "same-origin", keepalive: true }).catch(() => {})
  }

  async save() {
    if (this.saving) { this.queued = true; return }
    this.saving = true
    this.dirty = false
    this.#status("Saving…", "text-gray-500")
    try {
      const response = await fetch(this.urlValue, { method: "PATCH", body: this.#payload(), headers: this.#headers(), credentials: "same-origin" })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || `Save failed (${response.status})`)
      this.#status("Saved.", "text-emerald-400")
      clearTimeout(this.resetTimer)
      this.resetTimer = setTimeout(() => this.#status("", "text-gray-500"), 3000)
    } catch (error) {
      this.dirty = true
      this.#status(`Couldn't save: ${error.message}`, "text-amber-400")
    } finally {
      this.saving = false
      if (this.queued) { this.queued = false; this.save() }
    }
  }

  // Serialize the sheet as the server stores it: [{name, items: [{quantity, item}]}].
  // No prices: the pull sheet is for the cook line and never shows cost, so
  // the estimate is neither echoed into the page nor kept on an edited row.
  #categories() {
    return Array.from(this.categoriesTarget.querySelectorAll("[data-category]")).map(section => ({
      name: this.#text(section.querySelector('[data-field="name"]')),
      items: Array.from(section.querySelectorAll("[data-item]")).map(li => ({
        quantity: this.#text(li.querySelector('[data-field="quantity"]')),
        item: this.#text(li.querySelector('[data-field="item"]'))
      }))
    }))
  }

  #toTaste() {
    if (!this.hasToTasteTarget) return []
    return this.#text(this.toTasteTarget).split(",").map(s => s.trim()).filter(Boolean)
  }

  #payload() {
    const body = new FormData()
    body.append("event_url", this.eventUrlValue)
    body.append("base_key", this.baseKeyValue)
    body.append("categories", JSON.stringify(this.#categories()))
    body.append("to_taste", JSON.stringify(this.#toTaste()))
    return body
  }

  #headers() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    return { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest", ...(token ? { "X-CSRF-Token": token } : {}) }
  }

  #text(el) {
    return (el?.textContent || "").replace(/\s+/g, " ").trim()
  }

  #status(text, colorClass) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("text-gray-500", "text-emerald-400", "text-amber-400")
    this.statusTarget.classList.add(colorClass)
  }
}
