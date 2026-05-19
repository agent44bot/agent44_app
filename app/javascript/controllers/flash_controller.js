import { Controller } from "@hotwired/stimulus"

// Auto-dismisses a flash banner after `delay` ms (default 7000),
// sliding it up + fading it out, then removing the element so the
// page reflows.
export default class extends Controller {
  static values = { delay: { type: Number, default: 7000 } }

  connect() {
    this.timer = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  dismiss() {
    this.element.style.transition = "transform 0.4s ease, opacity 0.4s ease"
    this.element.style.transform  = "translateY(-1rem)"
    this.element.style.opacity    = "0"
    setTimeout(() => this.element.remove(), 400)
  }
}
