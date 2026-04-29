import { Controller } from "@hotwired/stimulus"

// Reveal/confirm flow for the "Delete account" card on /settings.
// For Nostr-only users (no password) we require typing "DELETE" before
// enabling the submit button. Email users confirm with their password,
// which the server re-checks.
export default class extends Controller {
  static targets = ["view", "form", "confirm", "submitBtn"]
  static values = { hasPassword: Boolean }

  connect() {
    if (!this.hasPasswordValue && this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = true
    }
  }

  open(event) {
    event?.preventDefault()
    this.viewTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
  }

  cancel(event) {
    event?.preventDefault()
    this.formTarget.classList.add("hidden")
    this.viewTarget.classList.remove("hidden")
    if (this.hasConfirmTarget) this.confirmTarget.value = ""
    if (!this.hasPasswordValue && this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = true
    }
  }

  checkConfirm() {
    if (!this.hasSubmitBtnTarget) return
    this.submitBtnTarget.disabled = this.confirmTarget.value.trim() !== "DELETE"
  }
}
