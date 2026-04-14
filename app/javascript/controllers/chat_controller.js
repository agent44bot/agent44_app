import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "input", "form"]
  static values = { url: String }

  connect() {
    this.lastTimestamp = new Date(Date.now() - 3600000).toISOString()
    this.scrollToBottom()
    this._interval = setInterval(() => this.poll(), 3000)
  }

  disconnect() {
    clearInterval(this._interval)
  }

  async poll() {
    try {
      const res = await fetch(`${this.urlValue}?since=${this.lastTimestamp}`)
      if (!res.ok) return
      const messages = await res.json()
      if (messages.length === 0) return

      // Check for new messages we don't already have
      const existing = new Set(
        Array.from(this.messagesTarget.querySelectorAll("[data-msg-id]"))
          .map(el => el.dataset.msgId)
      )

      let added = false
      messages.forEach(msg => {
        if (existing.has(String(msg.id))) {
          // Update status of existing message
          const el = this.messagesTarget.querySelector(`[data-msg-id="${msg.id}"]`)
          if (el) {
            const statusEl = el.querySelector("[data-status]")
            if (statusEl && msg.status !== "pending") {
              statusEl.textContent = msg.status === "delivered" ? "" : msg.status
            }
          }
          return
        }

        added = true
        this.appendMessage(msg)
        this.lastTimestamp = msg.created_at
      })

      if (added) this.scrollToBottom()
    } catch (_) { /* silent */ }
  }

  appendMessage(msg) {
    const isUser = msg.role === "user"
    const time = new Date(msg.created_at).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })

    const wrapper = document.createElement("div")
    wrapper.className = `flex ${isUser ? "justify-end" : "justify-start"}`
    wrapper.dataset.msgId = msg.id

    wrapper.innerHTML = `
      <div class="max-w-[80%] rounded-xl px-4 py-2.5 ${isUser ? "bg-orange-600 text-white" : "bg-gray-800 text-gray-200"}">
        ${!isUser ? `<p class="text-[10px] font-semibold text-orange-400 mb-1">${this.escapeHtml(msg.agent)}</p>` : ""}
        <p class="text-sm whitespace-pre-wrap">${this.escapeHtml(msg.content)}</p>
        <div class="flex items-center justify-end gap-2 mt-1">
          <span data-status class="text-[9px] ${isUser ? "text-orange-200" : "text-gray-500"}">${isUser && msg.status === "pending" ? "pending" : ""}</span>
          <span class="text-[9px] ${isUser ? "text-orange-200" : "text-gray-500"}">${time}</span>
        </div>
      </div>
    `

    // Remove the "no messages" placeholder if present
    const placeholder = this.messagesTarget.querySelector("p.text-center")
    if (placeholder) placeholder.remove()

    this.messagesTarget.appendChild(wrapper)
  }

  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
