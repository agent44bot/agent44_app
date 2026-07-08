import { Controller } from "@hotwired/stimulus"

// Live counter for the Echo listening-topics box. Counts non-empty lines and
// shows the "X only searches the first N" hint the moment the list grows past
// the X recent-search cap (MAX_X_QUERIES), so a manager isn't surprised that
// extra topics silently skip X. Updates as they type, not just on load.
export default class extends Controller {
  static targets = ["input", "capHint"]
  static values = { cap: Number }

  connect() {
    this.update()
  }

  update() {
    const lines = this.inputTarget.value
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.length > 0)
    const over = lines.length > this.capValue
    this.capHintTarget.classList.toggle("hidden", !over)
  }
}
