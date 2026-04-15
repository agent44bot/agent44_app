import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = {
    activeClasses: { type: String, default: "text-orange-600 border-orange-600 bg-orange-50/50" },
    inactiveClasses: { type: String, default: "text-gray-500 border-transparent" }
  }

  select(event) {
    const index = parseInt(event.currentTarget.dataset.tabIndex)
    const active = this.activeClassesValue.split(" ")
    const inactive = this.inactiveClassesValue.split(" ")

    this.tabTargets.forEach((tab, i) => {
      if (i === index) {
        tab.classList.add(...active)
        tab.classList.remove(...inactive)
      } else {
        tab.classList.remove(...active)
        tab.classList.add(...inactive)
      }
    })

    this.panelTargets.forEach((panel, i) => {
      panel.classList.toggle("hidden", i !== index)
    })
  }
}
