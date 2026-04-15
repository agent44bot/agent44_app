import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tooltip", "name", "when", "status", "price", "badge"]

  show(event) {
    const el = event.currentTarget
    const data = el.dataset

    this.nameTarget.textContent = data.tipName || ""
    this.whenTarget.textContent = data.tipWhen || ""
    this.statusTarget.textContent = data.tipStatus || ""
    this.statusTarget.className = `text-xs font-semibold ${data.tipStatusColor || "text-gray-400"}`
    this.priceTarget.textContent = data.tipPrice ? `$${data.tipPrice}` : ""

    const badge = data.tipBadge || ""
    const badgeColor = data.tipBadgeColor || "bg-gray-800 text-gray-400"
    this.badgeTarget.textContent = badge
    this.badgeTarget.className = `inline-block px-2 py-0.5 rounded-full text-[10px] font-semibold ${badgeColor}`
    this.badgeTarget.classList.toggle("hidden", !badge)

    const rect = el.getBoundingClientRect()
    const tip = this.tooltipTarget
    tip.classList.remove("hidden")

    const tipRect = tip.getBoundingClientRect()
    let left = rect.left + rect.width / 2 - tipRect.width / 2
    let top = rect.bottom + 8

    const margin = 8
    const maxLeft = window.innerWidth - tipRect.width - margin
    if (left < margin) left = margin
    if (left > maxLeft) left = maxLeft

    if (top + tipRect.height > window.innerHeight - margin) {
      top = rect.top - tipRect.height - 8
    }

    tip.style.left = `${left}px`
    tip.style.top = `${top}px`
  }

  hide() {
    this.tooltipTarget.classList.add("hidden")
  }
}
