import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["week", "label", "prev", "next"]

  connect() {
    this.index = 0
    this.render()
  }

  prev() {
    if (this.index > 0) {
      this.index--
      this.render()
    }
  }

  next() {
    if (this.index < this.weekTargets.length - 1) {
      this.index++
      this.render()
    }
  }

  render() {
    this.weekTargets.forEach((el, i) => {
      el.classList.toggle("hidden", i !== this.index)
    })
    const active = this.weekTargets[this.index]
    if (active && this.hasLabelTarget) {
      this.labelTarget.textContent = active.dataset.weekLabel || ""
    }
    if (this.hasPrevTarget) this.prevTarget.disabled = this.index === 0
    if (this.hasNextTarget) this.nextTarget.disabled = this.index === this.weekTargets.length - 1
  }
}
