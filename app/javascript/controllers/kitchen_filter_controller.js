import { Controller } from "@hotwired/stimulus"

// Filter the /kitchen List view by availability status.
// Chip click → show cards matching data-status; hide cards that don't;
// hide empty sections. "all" clears the filter.
export default class extends Controller {
  static targets = ["chip", "card", "section"]

  filter(event) {
    const status = event.currentTarget.dataset.filterStatus

    this.chipTargets.forEach(chip => {
      const active = chip.dataset.filterStatus === status
      const on  = chip.dataset.activeClasses.split(" ")
      const off = chip.dataset.inactiveClasses.split(" ")
      chip.classList.remove(...on, ...off)
      chip.classList.add(...(active ? on : off))
    })

    this.cardTargets.forEach(card => {
      const show = status === "all" || card.dataset.status === status
      card.classList.toggle("hidden", !show)
    })

    this.sectionTargets.forEach(section => {
      const visible = section.querySelectorAll('[data-kitchen-filter-target="card"]:not(.hidden)').length
      section.classList.toggle("hidden", visible === 0)
    })
  }
}
