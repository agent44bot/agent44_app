import { Controller } from "@hotwired/stimulus"

// Wraps the "Upload receipt" form: the styled button opens the hidden file
// picker, and choosing a file submits the form.
//
// Before submitting a PHOTO we downscale + recompress it in the browser. A
// full-resolution iPhone camera image is 5-12 MB and decoding it can OOM and
// crash the WKWebView on older devices; a ~2000px JPEG is small, safe, and
// still plenty sharp for the receipt reader. PDFs and anything that fails to
// process are submitted as-is.
export default class extends Controller {
  static values = {
    maxEdge: { type: Number, default: 2000 },
    quality: { type: Number, default: 0.8 }
  }

  open() {
    this.fileInput().click()
  }

  async submit() {
    const input = this.fileInput()
    const file = input.files && input.files[0]
    if (!file) return

    if (file.type && file.type.startsWith("image/")) {
      try {
        const smaller = await this.downscale(file)
        if (smaller && smaller.size < file.size) this.replaceFile(input, smaller)
      } catch (_) {
        // Any failure: just upload the original file unchanged.
      }
    }
    this.element.requestSubmit()
  }

  async downscale(file) {
    const source = await this.decode(file)
    const sw = source.width || source.naturalWidth
    const sh = source.height || source.naturalHeight
    if (!sw || !sh) return null

    const scale = Math.min(1, this.maxEdgeValue / Math.max(sw, sh))
    // Nothing to gain if it's already small in both dimensions and bytes.
    if (scale === 1 && file.size < 2_500_000) return null

    const w = Math.round(sw * scale)
    const h = Math.round(sh * scale)
    const canvas = document.createElement("canvas")
    canvas.width = w
    canvas.height = h
    canvas.getContext("2d").drawImage(source, 0, 0, w, h)
    if (source.close) source.close()

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", this.qualityValue))
    if (!blob) return null
    return new File([blob], this.jpegName(file.name), { type: "image/jpeg" })
  }

  // Prefer createImageBitmap (decodes off the main thread, honors EXIF
  // orientation); fall back to an <img> for older engines.
  decode(file) {
    if (window.createImageBitmap) {
      return createImageBitmap(file, { imageOrientation: "from-image" }).catch(() => this.decodeImg(file))
    }
    return this.decodeImg(file)
  }

  decodeImg(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file)
      const img = new Image()
      img.onload = () => { URL.revokeObjectURL(url); resolve(img) }
      img.onerror = (e) => { URL.revokeObjectURL(url); reject(e) }
      img.src = url
    })
  }

  replaceFile(input, file) {
    const dt = new DataTransfer()
    dt.items.add(file)
    input.files = dt.files
  }

  jpegName(name) {
    return (name || "receipt").replace(/\.[^.]+$/, "") + ".jpg"
  }

  fileInput() {
    return this.element.querySelector('input[type="file"]')
  }
}
