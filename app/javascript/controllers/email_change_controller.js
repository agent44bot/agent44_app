import { Controller } from "@hotwired/stimulus"

// Drives the "Change email" card on /settings.
//
// Flow: user clicks Change → form reveals → submits new email + current
// password → server verifies password, updates email, sends verification
// to the new address. On success we also refresh the iOS keychain
// credential so Face ID keeps working with the new email.
export default class extends Controller {
  static targets = [
    "view", "form", "currentEmail",
    "newEmail", "password", "error", "saveBtn"
  ]
  static values = { url: String }

  open(event) {
    event?.preventDefault()
    this.viewTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.newEmailTarget.focus()
  }

  cancel(event) {
    event?.preventDefault()
    this.formTarget.classList.add("hidden")
    this.viewTarget.classList.remove("hidden")
    this.#clear()
  }

  submit(event) {
    event?.preventDefault()
    const email_address = this.newEmailTarget.value.trim()
    const password = this.passwordTarget.value
    if (!email_address || !password) {
      this.#showError("Enter both a new email and your current password.")
      return
    }

    this.saveBtnTarget.disabled = true
    this.saveBtnTarget.textContent = "Saving…"
    this.#clearError()

    const csrf = document.querySelector('meta[name="csrf-token"]')
    fetch(this.urlValue, {
      method: "PATCH",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrf ? csrf.content : ""
      },
      body: JSON.stringify({ email_address, password })
    }).then(async (r) => {
      if (r.status === 401) {
        this.#showError("That password is incorrect.")
        return
      }
      const body = await r.json().catch(() => ({}))
      if (!r.ok) {
        this.#showError(body.error || "Couldn't update email.")
        return
      }
      await this.#refreshFaceIdCredential(body.email_address, password)
      this.currentEmailTarget.textContent = body.email_address
      this.#clear()
      this.formTarget.classList.add("hidden")
      this.viewTarget.classList.remove("hidden")
    }).catch(() => {
      this.#showError("Network error. Try again in a moment.")
    }).finally(() => {
      this.saveBtnTarget.disabled = false
      this.saveBtnTarget.textContent = "Save changes"
    })
  }

  // If Face ID is enabled on this device, replace the cached email so the
  // next biometric sign-in uses the new address.
  async #refreshFaceIdCredential(newEmail, password) {
    if (!window.Capacitor || !window.Capacitor.isNativePlatform()) return
    const Bio = window.Capacitor.Plugins.BiometricAuth
    if (!Bio) return
    try {
      const avail = await Bio.isAvailable()
      if (!avail.isAvailable || !avail.hasCredentials) return
      await Bio.saveCredentials({ username: newEmail, password })
    } catch (_) { /* keychain refresh is best-effort */ }
  }

  #showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  #clearError() {
    this.errorTarget.classList.add("hidden")
    this.errorTarget.textContent = ""
  }

  #clear() {
    this.newEmailTarget.value = ""
    this.passwordTarget.value = ""
    this.#clearError()
  }
}
