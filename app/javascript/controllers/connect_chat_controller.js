import { Controller } from "@hotwired/stimulus"

// Per-platform connection help chat. Posts the user's message (plus a trimmed
// history) to the workspace ai_chat endpoint, renders the reply, and, when the
// server returns cost (managers only), updates the shared live cost counter.
export default class extends Controller {
  static targets = ["log", "input", "send"]
  static values = { url: String, platform: String }

  connect() {
    this.history = []
  }

  async send(event) {
    event.preventDefault()
    const text = this.inputTarget.value.trim()
    if (!text || this.busy) return

    this.busy = true
    this.inputTarget.value = ""
    this.appendBubble("user", text)
    const thinking = this.appendBubble("assistant", "...")
    this.setBusy(true)

    try {
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content
      const resp = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf, "Accept": "application/json" },
        body: JSON.stringify({ platform: this.platformValue, message: text, history: this.history })
      })
      const data = await resp.json()

      if (resp.ok && data.ok) {
        thinking.textContent = data.reply
        this.history.push({ role: "user", content: text })
        this.history.push({ role: "assistant", content: data.reply })
        if (typeof data.month_billed === "number") {
          this.updateCounter(data)
        }
      } else {
        thinking.textContent = data.error || "Sorry, something went wrong. Please try again."
        thinking.classList.add("text-red-400")
      }
    } catch {
      thinking.textContent = "Network error. Please try again."
      thinking.classList.add("text-red-400")
    } finally {
      this.busy = false
      this.setBusy(false)
      this.scrollToBottom()
      this.inputTarget.focus()
    }
  }

  appendBubble(role, text) {
    const wrap = document.createElement("div")
    wrap.className = role === "user" ? "text-right" : "text-left"
    const bubble = document.createElement("span")
    bubble.className = role === "user"
      ? "inline-block rounded-lg px-3 py-2 bg-orange-600/90 text-white whitespace-pre-wrap break-words max-w-[85%] text-left"
      : "inline-block rounded-lg px-3 py-2 bg-gray-800 text-gray-100 whitespace-pre-wrap break-words max-w-[85%]"
    bubble.textContent = text
    wrap.appendChild(bubble)
    this.logTarget.appendChild(wrap)
    this.scrollToBottom()
    return bubble
  }

  // Updates the shared cost counter (one per page) and flashes the billed delta.
  // The server sends month_billed always (when allowed) and month_raw only to
  // owner/site-admin viewers, so we update whichever spans exist.
  updateCounter(data) {
    const billedEl = document.getElementById("ws-ai-cost-billed")
    if (billedEl && typeof data.month_billed === "number") {
      billedEl.textContent = "$" + data.month_billed.toFixed(4)
    }
    const rawEl = document.getElementById("ws-ai-cost-raw")
    if (rawEl && typeof data.month_raw === "number") {
      rawEl.textContent = "$" + data.month_raw.toFixed(4)
    }
    const delta = data.cost_billed
    if (typeof delta === "number" && delta > 0) {
      const flash = document.getElementById("ws-ai-cost-delta")
      if (flash) {
        flash.textContent = "+$" + delta.toFixed(4)
        flash.classList.remove("opacity-0")
        clearTimeout(this._flashTimer)
        this._flashTimer = setTimeout(() => flash.classList.add("opacity-0"), 2000)
      }
    }
  }

  setBusy(on) {
    if (this.hasSendTarget) {
      this.sendTarget.disabled = on
      this.sendTarget.textContent = on ? "..." : "Ask"
    }
  }

  scrollToBottom() {
    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }
}
