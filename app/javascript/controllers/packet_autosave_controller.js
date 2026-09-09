import { Controller } from "@hotwired/stimulus"

// Live editing for the recipe packet: save the form about a second after the
// last keystroke and swap the PDF preview to the fresh file, so a change to
// the title, an ingredient, or the layout selects shows up without clicking
// Save. The Save button still works (a full submit) for anyone who prefers it.
//
// Wraps both the form and the preview: the form carries the input/change
// actions, the iframe is the frame target, the status span narrates.
//
// Nothing typed is ever dropped: leaving the page (Done link, back button,
// tab close, Turbo visit) flushes a pending save with a keepalive request,
// and an edit made while a save is in flight is saved again once it lands.
export default class extends Controller {
  static targets = ["form", "frame", "status"]
  static values = { delay: { type: Number, default: 900 } }

  connect() {
    this.idle = this.hasStatusTarget ? this.statusTarget.textContent : ""
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

  // Any keystroke or select change: (re)start the countdown.
  changed() {
    this.dirty = true
    clearTimeout(this.timer)
    this.#status("Unsaved changes…", "text-gray-400")
    this.timer = setTimeout(() => this.save(), this.delayValue)
  }

  // A manual Save submits the whole form and reloads; drop any pending autosave.
  cancel() {
    clearTimeout(this.timer)
    this.dirty = false
  }

  // Leaving the page with an unsaved edit: send it now. keepalive lets the
  // request finish after the page is gone; the preview is not updated since
  // there is no page left to update.
  flush() {
    if (!this.dirty || !this.hasFormTarget) return
    clearTimeout(this.timer)
    this.dirty = false
    fetch(this.formTarget.action, {
      method: "POST",
      body: new FormData(this.formTarget),
      headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" },
      credentials: "same-origin",
      keepalive: true
    }).catch(() => {})
  }

  async save() {
    if (!this.hasFormTarget) return
    if (this.saving) { this.queued = true; return } // save again once this one lands
    this.saving = true
    this.dirty = false
    this.#status("Saving…", "text-gray-400")
    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST", // form carries _method=patch
        body: new FormData(this.formTarget),
        headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin"
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || `Save failed (${response.status})`)
      if (this.hasFrameTarget && data.preview_url) this.frameTarget.src = data.preview_url
      this.#status("Saved. Preview updated.", "text-emerald-400")
      clearTimeout(this.resetTimer)
      this.resetTimer = setTimeout(() => this.#status(this.idle, "text-gray-500"), 3000)
    } catch (error) {
      this.dirty = true
      this.#status(`Couldn't save: ${error.message}`, "text-amber-400")
    } finally {
      this.saving = false
      if (this.queued) { this.queued = false; this.save() }
    }
  }

  #status(text, colorClass) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("text-gray-500", "text-gray-400", "text-emerald-400", "text-amber-400")
    this.statusTarget.classList.add(colorClass)
  }
}
