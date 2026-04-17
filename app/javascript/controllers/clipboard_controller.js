import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]
  static values = { url: String }

  copy() {
    const url = this.hasUrlValue ? this.urlValue : window.location.href
    navigator.clipboard.writeText(url).then(() => {
      this.labelTarget.textContent = "Copied!"
      setTimeout(() => { this.labelTarget.textContent = "Share" }, 1500)
    })
  }
}
