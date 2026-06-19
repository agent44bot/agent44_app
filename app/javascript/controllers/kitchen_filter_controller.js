import { Controller } from "@hotwired/stimulus"

// Live search for Sam's class list. Typing in the search box filters event
// cards by their data-search-text (class name + dish/menu + chef). All classes
// are already on the page, so this filters instantly with no server round-trip.
//
// Weeks start collapsed; a week containing a match is auto-expanded so the hit
// is visible. Clearing the search re-collapses only the weeks the search opened
// (weeks the user opened by hand are left alone) and shows everything again.
export default class extends Controller {
  static targets = ["card", "section", "query", "empty"]

  connect() {
    this.searchExpanded = new Set()
  }

  search() {
    const q = (this.hasQueryTarget ? this.queryTarget.value : "").trim().toLowerCase()

    this.cardTargets.forEach(card => {
      const text = card.dataset.searchText || ""
      card.classList.toggle("hidden", q !== "" && !text.includes(q))
    })

    let anyVisible = false
    this.sectionTargets.forEach(section => {
      const matches = section.querySelectorAll(
        '[data-kitchen-filter-target="card"]:not(.hidden)'
      ).length
      section.classList.toggle("hidden", matches === 0)
      if (matches > 0) anyVisible = true

      if (q !== "" && matches > 0) {
        this.#expand(section)
      } else if (q === "") {
        this.#restore(section)
      }
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", q === "" || anyVisible)
    }
  }

  // Open a collapsed week so a match inside it is visible; remember that we
  // opened it so we can put it back when the search is cleared.
  #expand(section) {
    const body = section.querySelector('[data-collapsible-target="body"]')
    if (!body || !body.classList.contains("hidden")) return
    body.classList.remove("hidden")
    section.querySelector('[data-collapsible-target="icon"]')?.classList.remove("-rotate-90")
    this.searchExpanded.add(section)
  }

  // Re-collapse a week only if the search was what opened it.
  #restore(section) {
    if (!this.searchExpanded.has(section)) return
    const body = section.querySelector('[data-collapsible-target="body"]')
    if (body) {
      body.classList.add("hidden")
      section.querySelector('[data-collapsible-target="icon"]')?.classList.add("-rotate-90")
    }
    this.searchExpanded.delete(section)
  }
}
