import { Controller } from "@hotwired/stimulus"

// Opens the printable schedule in a new tab without triggering the
// surrounding card link. preventDefault() stops the ancestor <a> from
// navigating; the print page auto-prints when given ?autoprint=1.
export default class extends Controller {
  static values = { url: String }

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    window.open(this.urlValue, "_blank", "noopener")
  }
}
