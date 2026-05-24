import { Controller } from "@hotwired/stimulus"

// Browser-only chat with Super Agent. Holds the full conversation in
// memory, POSTs the history to nyk_ask_message_path each turn, appends
// the reply. No persistence — refresh = fresh chat.
export default class extends Controller {
  static targets = ["messages", "input", "send", "form", "empty", "reset"]
  static values  = { endpoint: String }

  connect() {
    this.history = []

    // Keep the chat box sized to the *visible* viewport. On iOS the soft
    // keyboard shrinks the visual viewport but not 100vh, so a viewport-tall
    // box leaves its bottom-anchored input behind the keyboard — Safari then
    // scrolls the whole page up to reveal it, shifting the view. Resizing the
    // box to the visual viewport keeps the input above the keyboard, so the
    // page never needs to scroll. Falls back to the CSS height when the
    // VisualViewport API is missing (desktop / older browsers).
    this._fit = this._fit.bind(this)
    if (window.visualViewport) {
      window.visualViewport.addEventListener("resize", this._fit)
      window.visualViewport.addEventListener("scroll", this._fit)
      this.inputTarget.addEventListener("focus", this._fit)
      this.inputTarget.addEventListener("blur", this._fit)
      this._fit()
    }

    // Don't autofocus on touch devices — it pops the keyboard (and shifts the
    // view) on every page load / Turbo restore. Desktop keeps the convenience.
    if (!window.matchMedia("(pointer: coarse)").matches) this.inputTarget.focus()
  }

  disconnect() {
    if (window.visualViewport) {
      window.visualViewport.removeEventListener("resize", this._fit)
      window.visualViewport.removeEventListener("scroll", this._fit)
    }
  }

  _fit() {
    const vv = window.visualViewport
    if (!vv) return
    // Distance from the top of the visible viewport to the top of the box,
    // then fill down to just shy of the viewport bottom (the keyboard top).
    const top = this.element.getBoundingClientRect().top
    this.element.style.minHeight = "0px" // let the inline 500px min give way
    this.element.style.height = Math.max(vv.height - top - 8, 220) + "px"
    // Keep the latest messages in view as the box resizes around the keyboard.
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  reset() {
    this.history = []
    this.messagesTarget.querySelectorAll(":scope > div:not([data-super-chat-target=empty])")
      .forEach(el => el.remove())
    if (this.hasEmptyTarget) this.emptyTarget.hidden = false
    if (this.hasResetTarget) this.resetTarget.hidden = true
    this.inputTarget.focus()
  }

  useExample(event) {
    const text = event.currentTarget.dataset.example
    if (!text) return
    this.inputTarget.value = text
    this.formTarget.requestSubmit()
  }

  async submit(event) {
    event.preventDefault()
    const text = this.inputTarget.value.trim()
    if (!text) return

    this.inputTarget.value = ""
    this._setBusy(true)
    this._hideEmpty()

    this.history.push({ role: "user", content: text })
    this._renderBubble("user", text)
    const thinking = this._renderBubble("assistant", "...", { thinking: true })

    try {
      const reply = await this._postMessages(this.history)
      thinking.remove()
      this.history.push({ role: "assistant", content: reply })
      this._renderBubble("assistant", reply)
    } catch (err) {
      thinking.remove()
      this._renderBubble("assistant", `Sorry — ${err.message || "something went wrong"}.`, { error: true })
      this.history.pop() // drop the user turn so retry doesn't double-up
    } finally {
      this._setBusy(false)
      this.inputTarget.focus()
    }
  }

  async _postMessages(messages) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const res = await fetch(this.endpointValue, {
      method: "POST",
      headers: {
        "Content-Type":   "application/json",
        "Accept":         "application/json",
        "X-CSRF-Token":   csrf || ""
      },
      body: JSON.stringify({ messages })
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
    if (!data.reply) throw new Error("empty reply")
    return data.reply
  }

  _renderBubble(role, text, opts = {}) {
    const isUser = role === "user"
    const wrap   = document.createElement("div")
    wrap.className = `flex ${isUser ? "justify-end" : "justify-start"}`

    const bubble = document.createElement("div")
    const baseCls = "max-w-[85%] rounded-2xl px-4 py-2.5 text-sm whitespace-pre-wrap"
    const colorCls = isUser
      ? "bg-orange-600 text-white"
      : opts.error
        ? "bg-red-950 border border-red-900 text-red-200"
        : opts.thinking
          ? "bg-gray-900 text-gray-500 italic"
          : "bg-gray-900 text-gray-200 border border-gray-800"
    bubble.className = `${baseCls} ${colorCls}`
    bubble.textContent = text

    wrap.appendChild(bubble)
    this.messagesTarget.appendChild(wrap)
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    return wrap
  }

  _hideEmpty() {
    if (this.hasEmptyTarget) this.emptyTarget.hidden = true
    if (this.hasResetTarget) this.resetTarget.hidden = false
  }

  _setBusy(busy) {
    this.inputTarget.disabled = busy
    this.sendTarget.disabled  = busy
    this.sendTarget.textContent = busy ? "..." : "Send"
  }
}
