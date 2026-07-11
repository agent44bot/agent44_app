import { Controller } from "@hotwired/stimulus"

// Live, client-side filter for the recipe library, mirroring the snappy class
// list search (kitchen_filter_controller). Every packet is already on the page;
// typing does an instant case-insensitive substring match over each row's
// data-search-text (packet title + recipe titles + ingredients + directions),
// so "ginger" filters to packets that use it with no server round-trip.
export default class extends Controller {
  static targets = ["card", "query", "empty", "count"]
  // hideEmpty: on the compact "copy an existing packet" box, keep the list
  // hidden until the user types, so it doesn't dump every packet up front.
  // The full library page leaves it false and shows everything.
  static values = { hideEmpty: Boolean }

  connect() { this.search() }

  search() {
    const q = (this.hasQueryTarget ? this.queryTarget.value : "").trim().toLowerCase()
    const hideAll = this.hideEmptyValue && q === ""

    let visible = 0
    this.cardTargets.forEach(card => {
      const match = !hideAll && (q === "" || (card.dataset.searchText || "").includes(q))
      card.classList.toggle("hidden", !match)
      if (match) visible++
    })

    if (this.hasEmptyTarget) {
      // Only flag "no matches" once the user has actually typed something.
      this.emptyTarget.classList.toggle("hidden", hideAll || visible !== 0)
    }
    if (this.hasCountTarget) {
      this.countTarget.textContent = hideAll ? ""
        : q === "" ? `${visible} ${visible === 1 ? "recipe" : "recipes"}`
        : `${visible} matching "${q}"`
    }
  }
}
