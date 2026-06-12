import { Controller } from "@hotwired/stimulus"

// Hover (desktop) or tap (mobile) a class tag on the grocery list to see that
// class's recipe in a popover, with the ingredient for that grocery row
// highlighted. Recipe lines per class come in as a tag -> [lines] map.
//
//   <div data-controller="recipe-popover" data-recipe-popover-recipes-value="{...}">
//     <span data-action="mouseenter->recipe-popover#show mouseleave->recipe-popover#hide click->recipe-popover#toggle"
//           data-recipe-popover-tag-param="Korean Barbecue 6/20"
//           data-recipe-popover-item-param="Carrots">Korean Barbecue 6/20</span>
//     <div data-recipe-popover-target="panel" class="hidden">...</div>
//   </div>
export default class extends Controller {
  static values = { recipes: Object }
  static targets = ["panel", "title", "list"]

  connect() {
    this.pinned = false
    this.onDocClick = this.onDocClick.bind(this)
    document.addEventListener("click", this.onDocClick)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocClick)
  }

  show(event) {
    if (this.pinned) return // a tap-opened popover stays until dismissed
    this.render(event.params.tag, event.params.item)
    this.place(event.currentTarget)
  }

  hide() {
    if (this.pinned) return
    this.panelTarget.classList.add("hidden")
  }

  // Tap: pin open; tapping the same chip again closes it.
  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    const sameOpen = this.pinned && this.currentTag === event.params.tag && !this.panelTarget.classList.contains("hidden")
    if (sameOpen) {
      this.pinned = false
      this.panelTarget.classList.add("hidden")
      return
    }
    this.pinned = true
    this.render(event.params.tag, event.params.item)
    this.place(event.currentTarget)
  }

  onDocClick(event) {
    if (!this.pinned) return
    if (this.panelTarget.contains(event.target)) return
    if (event.target.closest("[data-recipe-popover-tag-param]")) return
    this.pinned = false
    this.panelTarget.classList.add("hidden")
  }

  render(tag, item) {
    this.currentTag = tag
    const lines = this.recipesValue[tag] || []
    const words = (item || "").toLowerCase().match(/[a-z]{3,}/g) || []
    const matches = (line) => words.some((w) => line.toLowerCase().includes(w))

    this.titleTarget.textContent = tag
    this.listTarget.innerHTML = ""
    let firstMatch = null
    lines.forEach((line) => {
      const li = document.createElement("li")
      li.textContent = line
      const hit = matches(line)
      li.className = hit
        ? "px-1.5 py-0.5 rounded bg-yellow-200 text-gray-900 font-semibold"
        : "px-1.5 py-0.5 text-gray-300"
      this.listTarget.appendChild(li)
      if (hit && !firstMatch) firstMatch = li
    })
    this.panelTarget.classList.remove("hidden")
    // Scroll the highlighted ingredient into view (it may be far down a long
    // recipe); otherwise start at the top.
    this.panelTarget.scrollTop = firstMatch ? Math.max(0, firstMatch.offsetTop - 56) : 0
  }

  // Position the panel near the chip, clamped to the viewport.
  place(chip) {
    const r = chip.getBoundingClientRect()
    const p = this.panelTarget
    p.style.position = "fixed"
    p.style.visibility = "hidden"
    p.classList.remove("hidden")
    const pw = p.offsetWidth
    const ph = p.offsetHeight
    let left = Math.min(r.left, window.innerWidth - pw - 12)
    left = Math.max(12, left)
    let top = r.bottom + 6
    if (top + ph > window.innerHeight - 8) top = Math.max(8, r.top - ph - 6)
    p.style.left = `${left}px`
    p.style.top = `${top}px`
    p.style.visibility = "visible"
  }
}
