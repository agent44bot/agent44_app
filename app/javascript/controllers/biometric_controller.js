import { Controller } from "@hotwired/stimulus"

// Drives the Face ID toggle on /settings.
//
// States:
//   - web (not Capacitor)   → show web fallback panel, hide everything else
//   - unsupported           → show unsupported panel
//   - on  (hasCredentials)  → show disable button
//   - off (no credentials)  → show password field + enable button
//
// Enable flow: POST password to verify-url; on 204, save to keychain.
// Disable flow: delete keychain credentials.
export default class extends Controller {
  static targets = [
    "card", "status",
    "onState", "offState", "unsupportedState", "webState",
    "password", "error",
    "enableBtn", "disableBtn"
  ]
  static values = { verifyUrl: String, email: String }

  connect() {
    if (!window.Capacitor || !window.Capacitor.isNativePlatform()) {
      this.webStateTarget.classList.remove("hidden")
      return
    }

    const Bio = window.Capacitor.Plugins.BiometricAuth
    if (!Bio) {
      this.#showWeb()
      return
    }
    this.bio = Bio
    this.cardTarget.classList.remove("hidden")
    this.webStateTarget.classList.add("hidden")

    Bio.isAvailable().then((result) => {
      if (!result.isAvailable) {
        this.#setStatus("Unavailable", "bg-gray-800 text-gray-500")
        this.unsupportedStateTarget.classList.remove("hidden")
        return
      }
      if (result.hasCredentials) {
        this.#renderOn()
      } else {
        this.#renderOff()
      }
    }).catch(() => { this.#showWeb() })
  }

  enable() {
    const password = this.passwordTarget.value
    if (!password) { this.#showError("Please enter your password."); return }

    this.enableBtnTarget.disabled = true
    this.enableBtnTarget.textContent = "Verifying…"
    this.#clearError()

    const csrf = document.querySelector('meta[name="csrf-token"]')
    fetch(this.verifyUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrf ? csrf.content : ""
      },
      body: JSON.stringify({ password })
    }).then((r) => {
      if (r.status === 204) {
        return this.bio.saveCredentials({
          username: this.emailValue,
          password: password
        }).then(() => {
          this.passwordTarget.value = ""
          this.#renderOn()
        })
      }
      if (r.status === 401) {
        this.#showError("That password is incorrect.")
      } else {
        this.#showError("Couldn't verify right now. Try again in a moment.")
      }
    }).catch(() => {
      this.#showError("Network error. Please try again.")
    }).finally(() => {
      this.enableBtnTarget.disabled = false
      this.enableBtnTarget.textContent = "Turn on Face ID"
    })
  }

  disable() {
    if (!confirm("Turn off Face ID for this device? You'll need your password to sign in again.")) return

    this.disableBtnTarget.disabled = true
    this.disableBtnTarget.textContent = "Turning off…"

    this.bio.deleteCredentials().then(() => {
      this.#renderOff()
    }).catch(() => {
      // Even if plugin rejects, fall back to the off state so UI is honest.
      this.#renderOff()
    }).finally(() => {
      this.disableBtnTarget.disabled = false
      this.disableBtnTarget.textContent = "Turn off Face ID"
    })
  }

  #renderOn() {
    this.#setStatus("On", "bg-green-900/60 text-green-300")
    this.onStateTarget.classList.remove("hidden")
    this.offStateTarget.classList.add("hidden")
    this.unsupportedStateTarget.classList.add("hidden")
  }

  #renderOff() {
    this.#setStatus("Off", "bg-gray-800 text-gray-400")
    this.offStateTarget.classList.remove("hidden")
    this.onStateTarget.classList.add("hidden")
    this.unsupportedStateTarget.classList.add("hidden")
  }

  #setStatus(text, classes) {
    this.statusTarget.textContent = text
    this.statusTarget.className = "text-xs font-semibold px-2 py-1 rounded-full " + classes
  }

  #showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  #clearError() {
    this.errorTarget.classList.add("hidden")
    this.errorTarget.textContent = ""
  }

  #showWeb() {
    this.cardTarget.classList.add("hidden")
    this.webStateTarget.classList.remove("hidden")
  }
}
