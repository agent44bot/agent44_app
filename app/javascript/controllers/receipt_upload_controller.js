import { Controller } from "@hotwired/stimulus"

// Wraps the "Upload receipt" form: the styled button opens the hidden file
// picker, and choosing a file submits the form immediately (no extra click).
export default class extends Controller {
  open() {
    this.fileInput().click()
  }

  submit() {
    if (this.fileInput().files.length) this.element.requestSubmit()
  }

  fileInput() {
    return this.element.querySelector('input[type="file"]')
  }
}
