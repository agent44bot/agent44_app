import { Controller } from "@hotwired/stimulus"

// Hover flyout for the member-avatar stack. The menu is portaled to <body> and
// positioned fixed, so no ancestor's overflow (headers, collapsible cards) can
// clip it. Right-aligned just below the trigger.
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.hideTimer = null
    this.menu = this.menuTarget
    this.menu.remove()
    document.body.appendChild(this.menu)
    Object.assign(this.menu.style, { position: "fixed", display: "none" })

    this.onEnter = () => this.show()
    this.onLeave = () => this.scheduleHide()
    this.element.addEventListener("mouseenter", this.onEnter)
    this.element.addEventListener("mouseleave", this.onLeave)
    this.menu.addEventListener("mouseenter", this.onEnter)
    this.menu.addEventListener("mouseleave", this.onLeave)
  }

  disconnect() {
    clearTimeout(this.hideTimer)
    this.element.removeEventListener("mouseenter", this.onEnter)
    this.element.removeEventListener("mouseleave", this.onLeave)
    if (this.menu && this.menu.parentElement === document.body) this.menu.remove()
  }

  show() {
    clearTimeout(this.hideTimer)
    const r = this.element.getBoundingClientRect()
    Object.assign(this.menu.style, {
      display: "block",
      top: `${Math.round(r.bottom + 8)}px`,
      right: `${Math.round(window.innerWidth - r.right)}px`,
      left: "auto",
    })
  }

  scheduleHide() {
    this.hideTimer = setTimeout(() => { this.menu.style.display = "none" }, 120)
  }
}
