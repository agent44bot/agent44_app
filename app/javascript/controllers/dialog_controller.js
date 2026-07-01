import { Controller } from "@hotwired/stimulus"

// Generic native-<dialog> modal: overlay a panel instead of pushing the page.
// ESC closes it (a <dialog> freebie); so do the close button and a backdrop
// click. Used for the "Add a class" form on Sam's list.
export default class extends Controller {
  static targets = ["modal"]

  open() {
    this.modalTarget.showModal()
  }

  close() {
    this.modalTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.modalTarget) this.close()
  }
}
