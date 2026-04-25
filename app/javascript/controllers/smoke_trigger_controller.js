import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "status"]
  static values = { url: String }

  async trigger(event) {
    event.preventDefault()

    const btn = this.buttonTarget
    btn.disabled = true
    btn.textContent = "Triggering…"
    btn.classList.add("opacity-60", "cursor-not-allowed")

    if (this.hasStatusTarget) {
      this.statusTarget.innerHTML = ""
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const res = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken
        },
        credentials: "same-origin"
      })

      const data = await res.json()

      if (res.ok && data.ok) {
        btn.textContent = "Run started"
        btn.classList.remove("bg-orange-500", "hover:bg-orange-400")
        btn.classList.add("bg-green-600")
        if (this.hasStatusTarget && data.workflow_url) {
          this.statusTarget.innerHTML = `<a href="${data.workflow_url}" target="_blank" rel="noopener" class="text-orange-400 hover:text-orange-300 underline">View on GitHub Actions ↗</a>`
        }
      } else {
        this.showError(data.error || `Failed (${res.status})`)
      }
    } catch (err) {
      this.showError(err.message || "Network error")
    }
  }

  showError(message) {
    const btn = this.buttonTarget
    btn.textContent = "Run Smoke Test"
    btn.disabled = false
    btn.classList.remove("opacity-60", "cursor-not-allowed")
    if (this.hasStatusTarget) {
      this.statusTarget.innerHTML = `<span class="text-red-400">${message}</span>`
    }
  }
}
