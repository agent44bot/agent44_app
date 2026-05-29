import { Controller } from "@hotwired/stimulus"

// Copy the text of a source element to the clipboard — used by the apply kit
// (cover letter, screening answers). Stimulus, not inline JS, so it survives
// Turbo nav + CSP. Markup:
//   <div data-controller="copy-text">
//     <pre data-copy-text-target="source">...</pre>
//     <button data-action="copy-text#copy" data-copy-text-target="button">Copy</button>
//   </div>
export default class extends Controller {
  static targets = ["source", "button"]

  copy() {
    const text = this.sourceTarget.innerText
    navigator.clipboard.writeText(text).then(() => this.flash("Copied!")).catch(() => this.flash("Copy failed"))
  }

  flash(label) {
    if (!this.hasButtonTarget) return
    const original = this.buttonTarget.dataset.label || this.buttonTarget.textContent
    this.buttonTarget.dataset.label = original
    this.buttonTarget.textContent = label
    setTimeout(() => { this.buttonTarget.textContent = original }, 1500)
  }
}
