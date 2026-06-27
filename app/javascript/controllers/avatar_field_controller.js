import { Controller } from "@hotwired/stimulus"

// Instant local preview for the Settings profile-photo field. The server only
// shows the new avatar after Save + a round trip, which on a phone reads as
// "nothing happened" (this is what made an upload look like a failure). The
// moment a file is chosen we swap in a local object-URL preview so the change
// is visible right away. No upload happens here; the form still submits the
// original file for validation and storage.
export default class extends Controller {
  static targets = ["input", "preview", "fallback"]

  preview() {
    const file = this.inputTarget.files && this.inputTarget.files[0]
    if (!file || !file.type.startsWith("image/")) return

    const url = URL.createObjectURL(file)
    if (this.previousUrl) URL.revokeObjectURL(this.previousUrl)
    this.previousUrl = url

    this.previewTarget.src = url
    this.previewTarget.hidden = false
    if (this.hasFallbackTarget) this.fallbackTarget.hidden = true
  }

  disconnect() {
    if (this.previousUrl) URL.revokeObjectURL(this.previousUrl)
  }
}
