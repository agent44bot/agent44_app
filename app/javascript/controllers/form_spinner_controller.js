import { Controller } from "@hotwired/stimulus"

// Full-screen spinner overlay while a slow form submits (AI recipe generate /
// build, which take several seconds before the redirect). The thin Turbo
// progress bar alone is too subtle. The overlay is removed automatically when
// the next page renders (Turbo replaces <body>).
export default class extends Controller {
  static values = { message: { type: String, default: "Working…" } }

  show() {
    if (document.getElementById("form-spinner-overlay")) return
    const overlay = document.createElement("div")
    overlay.id = "form-spinner-overlay"
    overlay.className =
      "fixed inset-0 z-[100] flex flex-col items-center justify-center bg-gray-950/85 backdrop-blur-sm"
    overlay.innerHTML =
      '<svg class="animate-spin w-10 h-10 text-orange-500 mb-4" viewBox="0 0 24 24" fill="none">' +
        '<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>' +
        '<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"></path>' +
      '</svg>' +
      `<p class="text-gray-200 text-sm">${this.#escape(this.messageValue)}</p>` +
      '<p class="text-gray-500 text-xs mt-1">This can take a few seconds.</p>'
    document.body.appendChild(overlay)
  }

  #escape(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
