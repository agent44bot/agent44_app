import { Controller } from "@hotwired/stimulus"

// Full-screen spinner overlay while a slow form submits (AI recipe generate /
// build, which take several seconds before the redirect). The thin Turbo
// progress bar alone is too subtle. The overlay is removed automatically when
// the next page renders (Turbo replaces <body>).
export default class extends Controller {
  static values = { message: { type: String, default: "Working…" } }

  // Building a recipe from a big PDF is a synchronous Opus call (up to ~a
  // minute). The overlay is normally torn down when the next page renders, so
  // if it is still up after these marks the request is running long, or has
  // stalled/timed out, and the user needs a hint about what to do.
  static NUDGE_MS = 25000   // reassure: large menus just take a while
  static STALL_MS = 75000   // past a likely timeout: tell them what to try

  disconnect() {
    this.#clearTimers()
  }

  show() {
    if (document.getElementById("form-spinner-overlay")) return
    const overlay = document.createElement("div")
    overlay.id = "form-spinner-overlay"
    overlay.className =
      "fixed inset-0 z-[100] flex flex-col items-center justify-center bg-gray-950/85 backdrop-blur-sm px-6 text-center"
    overlay.innerHTML =
      '<svg class="animate-spin w-10 h-10 text-orange-500 mb-4" viewBox="0 0 24 24" fill="none">' +
        '<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>' +
        '<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"></path>' +
      '</svg>' +
      `<p class="text-gray-200 text-sm">${this.#escape(this.messageValue)}</p>` +
      '<p id="form-spinner-hint" class="text-gray-500 text-xs mt-1 max-w-sm">This can take a few seconds.</p>'
    document.body.appendChild(overlay)

    this.nudgeTimer = setTimeout(() => {
      this.#hint("Still working. A long or multi-recipe menu can take up to a minute, please keep this tab open.")
    }, this.constructor.NUDGE_MS)

    this.stallTimer = setTimeout(() => {
      this.#hint("This is taking longer than usual. The file may be too large to import at once. If it does not finish, try a smaller PDF, split the menu into two, or paste the recipes as text.")
    }, this.constructor.STALL_MS)
  }

  #hint(text) {
    const el = document.getElementById("form-spinner-hint")
    if (el) el.textContent = text
  }

  #clearTimers() {
    clearTimeout(this.nudgeTimer)
    clearTimeout(this.stallTimer)
  }

  #escape(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
