import { Controller } from "@hotwired/stimulus"

// Multi-file drop zone for the Send feedback form. Dropped or picked files are
// added to what is already chosen (not replacing it) and written back to the
// real <input type="file"> via DataTransfer, so the normal form submit posts
// them. Files of a type we don't take, over the size limit, or past the file
// cap are skipped with a note. The server still checks every upload.
// (dropzone_controller.js is the single-PDF version used on the kitchen pages.)
export default class extends Controller {
  static targets = ["input", "list", "note"]
  static values = { extensions: Array, maxFiles: Number, maxSize: Number }

  connect() {
    this.files = []
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
    this.add(Array.from(event.dataTransfer?.files || []))
  }

  // The picker replaces input.files, so fold its picks into the running list.
  picked() {
    this.add(Array.from(this.inputTarget.files || []))
  }

  add(incoming) {
    const skipped = []
    incoming.forEach((file) => {
      if (this.files.some((f) => f.name === file.name && f.size === file.size && f.lastModified === file.lastModified)) return
      if (!this.allowed(file)) {
        skipped.push(`${file.name} (not a file type we accept)`)
      } else if (file.size > this.maxSizeValue) {
        skipped.push(`${file.name} (over ${Math.round(this.maxSizeValue / 1048576)} MB)`)
      } else if (this.files.length >= this.maxFilesValue) {
        skipped.push(`${file.name} (limit is ${this.maxFilesValue} files)`)
      } else {
        this.files.push(file)
      }
    })

    const dt = new DataTransfer()
    this.files.forEach((f) => dt.items.add(f))
    this.inputTarget.files = dt.files
    this.render(skipped)
  }

  allowed(file) {
    const ext = file.name.toLowerCase().split(".").pop()
    return this.extensionsValue.includes(ext)
  }

  render(skipped) {
    this.listTarget.textContent = this.files.map((f) => f.name).join(", ")
    this.noteTarget.textContent = skipped.length ? `Skipped: ${skipped.join(", ")}` : ""
  }

  highlight(on) {
    this.element.style.borderColor = on ? "#f97316" : ""
    this.element.style.backgroundColor = on ? "rgba(249,115,22,0.10)" : ""
  }
}
