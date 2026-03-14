import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  select(event) {
    const index = parseInt(event.currentTarget.dataset.tabIndex)

    this.tabTargets.forEach((tab, i) => {
      if (i === index) {
        tab.classList.add("text-indigo-600", "border-indigo-600", "bg-indigo-50/50")
        tab.classList.remove("text-gray-500", "border-transparent")
      } else {
        tab.classList.remove("text-indigo-600", "border-indigo-600", "bg-indigo-50/50")
        tab.classList.add("text-gray-500", "border-transparent")
      }
    })

    this.panelTargets.forEach((panel, i) => {
      panel.classList.toggle("hidden", i !== index)
    })
  }
}
