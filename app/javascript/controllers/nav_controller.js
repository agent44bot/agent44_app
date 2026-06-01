import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    // Close the flyout when clicking anywhere outside this nav (page dead space
    // or other content). Bound once; removed on disconnect.
    this.closeOnOutsideClick = this.closeOnOutsideClick.bind(this)
    document.addEventListener("click", this.closeOnOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick)
  }

  toggle() {
    this.menuTarget.classList.toggle("hidden")
  }

  close() {
    this.menuTarget.classList.add("hidden")
  }

  closeOnOutsideClick(event) {
    // Clicks on the toggle button / inside the menu live within this.element and
    // are handled by toggle() — leave them alone. Only outside clicks close.
    if (this.element.contains(event.target)) return
    if (!this.hasMenuTarget || this.menuTarget.classList.contains("hidden")) return
    this.close()
  }
}
