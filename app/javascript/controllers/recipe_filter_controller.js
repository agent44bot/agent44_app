import { Controller } from "@hotwired/stimulus"

// Live, client-side filter for the recipe library, mirroring the snappy class
// list search (kitchen_filter_controller). Every packet is already on the page;
// typing does an instant case-insensitive substring match over each row's
// data-search-text (packet title + recipe titles + ingredients + directions),
// so "ginger" filters to packets that use it with no server round-trip.
export default class extends Controller {
  static targets = ["card", "query", "empty", "count"]

  search() {
    const q = (this.hasQueryTarget ? this.queryTarget.value : "").trim().toLowerCase()

    let visible = 0
    this.cardTargets.forEach(card => {
      const match = q === "" || (card.dataset.searchText || "").includes(q)
      card.classList.toggle("hidden", !match)
      if (match) visible++
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", visible !== 0)
    }
    if (this.hasCountTarget) {
      this.countTarget.textContent = q === ""
        ? `${visible} ${visible === 1 ? "recipe" : "recipes"}`
        : `${visible} matching "${q}"`
    }
  }
}
