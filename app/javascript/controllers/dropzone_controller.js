import { Controller } from "@hotwired/stimulus"

// Drag-and-drop wrapper around a hidden <input type="file">. Clicking the zone
// opens the file picker; dropping a file onto it (or picking one) assigns it to
// the input so the normal form submit still posts it. Stimulus, not inline JS,
// so it survives Turbo nav + the app CSP. Markup:
//   <div data-controller="dropzone" data-action="click->dropzone#browse
//          dragover->dropzone#over dragleave->dropzone#leave drop->dropzone#drop">
//     <input type="file" data-dropzone-target="input" class="hidden"
//            data-action="change->dropzone#changed">
//     <span data-dropzone-target="name">No file chosen</span>
//   </div>
export default class extends Controller {
  static targets = ["input", "name"]
  static values = { accept: String }

  browse(event) {
    // Don't re-open the picker when the click originated on the input itself.
    if (event.target !== this.inputTarget) this.inputTarget.click()
  }

  over(event) {
    event.preventDefault()
    this.highlight(true)
  }

  leave(event) {
    event.preventDefault()
    this.highlight(false)
  }

  drop(event) {
    event.preventDefault()
    this.highlight(false)
    const files = event.dataTransfer?.files
    if (!files || files.length === 0) return
    const file = files[0]
    if (!this.accepted(file)) {
      this.setName("That is not a PDF. Please drop a PDF file.")
      return
    }
    // Assign the dropped file to the real input via DataTransfer so the form
    // submits it unchanged.
    const dt = new DataTransfer()
    dt.items.add(file)
    this.inputTarget.files = dt.files
    this.setName(file.name)
  }

  changed() {
    const file = this.inputTarget.files?.[0]
    this.setName(file ? file.name : "No file chosen")
  }

  accepted(file) {
    if (!this.hasAcceptValue || this.acceptValue.trim() === "") return true
    return this.acceptValue.split(",").some((a) => {
      a = a.trim()
      return a && (file.type === a || file.name.toLowerCase().endsWith(a.replace(/^.*\//, ".")))
    }) || file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf")
  }

  // Toggle the drag-over look via inline styles, so no extra CSS file is
  // needed (and the app CSP allows inline style attributes).
  highlight(on) {
    this.element.style.borderColor = on ? "#f97316" : ""
    this.element.style.backgroundColor = on ? "rgba(249,115,22,0.10)" : ""
  }

  setName(text) {
    if (this.hasNameTarget) this.nameTarget.textContent = text
  }
}
