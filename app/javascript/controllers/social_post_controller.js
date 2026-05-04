import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleBtn", "preview", "previewText", "copyBtn", "saveBtn", "enhanceBtn",
                     "status", "postedStatus", "postedCheckbox", "thumbnail", "imageHint",
                     "idea", "ideaCallout"]

  IDEA_CALLOUT_STORAGE_KEY = "nyk:idea-field-seen"
  static values = {
    name: String,
    date: String,
    time: String,
    price: String,
    spots: Number,
    capacity: Number,
    url: String,
    description: String,
    logUrl: String,
    enhanceUrl: String,
    imageUrl: { type: String, default: "" },
    enhancedText: { type: String, default: "" },
    posted: { type: Boolean, default: false }
  }

  toggle() {
    const panel = this.previewTarget
    const isHidden = panel.classList.contains("hidden")

    if (isHidden) {
      this.previewTextTarget.textContent = this.enhancedTextValue || this.buildPost()
      panel.classList.remove("hidden")
      this.toggleBtnTarget.textContent = "Hide preview"
      this._maybeShowIdeaCallout()
    } else {
      panel.classList.add("hidden")
      this.toggleBtnTarget.textContent = "Preview post"
    }
  }

  dismissIdeaCallout() {
    if (!this.hasIdeaCalloutTarget) return
    this.ideaCalloutTarget.classList.add("hidden")
    try { localStorage.setItem(this.IDEA_CALLOUT_STORAGE_KEY, "1") } catch (_) {}
  }

  _maybeShowIdeaCallout() {
    if (!this.hasIdeaCalloutTarget) return
    let seen = false
    try { seen = localStorage.getItem(this.IDEA_CALLOUT_STORAGE_KEY) === "1" } catch (_) {}
    if (!seen) this.ideaCalloutTarget.classList.remove("hidden")
  }

  copy() {
    const text = this.previewTextTarget.textContent
    navigator.clipboard.writeText(text).then(() => {
      const btn = this.copyBtnTarget
      btn.textContent = "Copied!"
      btn.classList.remove("bg-blue-600", "hover:bg-blue-500")
      btn.classList.add("bg-green-600")
      setTimeout(() => {
        btn.textContent = "Copy to clipboard"
        btn.classList.remove("bg-green-600")
        btn.classList.add("bg-blue-600", "hover:bg-blue-500")
      }, 2000)

      if (this.hasStatusTarget) {
        this.statusTarget.textContent = "Copied just now"
        this.statusTarget.className = "text-green-500"
        const prev = this.statusTarget.previousElementSibling
        if (prev && prev.innerHTML === "") prev.innerHTML = "&middot;"
      }

      this.logAction("copy")

      // Save the current text (may include manual edits) to DB
      this.enhancedTextValue = text
      this.saveText(text)
    })
  }

  async saveImage() {
    if (!this.imageUrlValue) return

    const img = this.hasThumbnailTarget ? this.thumbnailTarget : null

    try {
      // Fetch the image and trigger a download (saves to camera roll on iOS)
      const resp = await fetch(this.imageUrlValue)
      const blob = await resp.blob()
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      // Extract filename from URL
      const filename = this.imageUrlValue.split("/").pop().split("?")[0] || "event-image.jpg"
      a.download = filename
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)

      if (img && this.hasImageHintTarget) {
        img.style.outline = "2px solid #22c55e"
        this.imageHintTarget.textContent = "Image saved!"
        this.imageHintTarget.classList.replace("text-gray-500", "text-green-500")
        setTimeout(() => {
          img.style.outline = ""
          this.imageHintTarget.textContent = "Tap to save image"
          this.imageHintTarget.classList.replace("text-green-500", "text-gray-500")
        }, 2000)
      }
    } catch {
      // Fallback: open image in new tab
      window.open(this.imageUrlValue, "_blank")
    }
  }

  markDirty() {
    if (this.hasSaveBtnTarget) {
      this.saveBtnTarget.classList.remove("hidden")
    }
  }

  saveDraft() {
    const text = this.previewTextTarget.textContent
    this.enhancedTextValue = text
    this.saveText(text)

    const btn = this.saveBtnTarget
    btn.textContent = "Saved!"
    btn.classList.remove("bg-green-600", "hover:bg-green-500")
    btn.classList.add("bg-gray-600")
    setTimeout(() => {
      btn.textContent = "Save draft"
      btn.classList.remove("bg-gray-600")
      btn.classList.add("bg-green-600", "hover:bg-green-500")
      btn.classList.add("hidden")
    }, 2000)
  }

  async enhance() {
    const btn = this.enhanceBtnTarget
    const originalText = btn.textContent
    btn.textContent = "Enhancing..."
    btn.disabled = true
    btn.classList.add("opacity-50")

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const draft = this.previewTextTarget.textContent
    const idea = this.hasIdeaTarget ? this.ideaTarget.value.trim() : ""

    try {
      const resp = await fetch(this.enhanceUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
        body: JSON.stringify({
          draft,
          idea,
          event_url: this.urlValue,
          event_name: this.nameValue,
          event_description: this.descriptionValue,
          event_date: this.dateValue,
          event_price: this.priceValue
        })
      })

      const data = await resp.json()

      if (resp.ok && data.enhanced) {
        this.enhancedTextValue = data.enhanced
        this.previewTextTarget.textContent = data.enhanced
        btn.textContent = "✨ Enhanced!"
        btn.classList.remove("opacity-50", "bg-purple-600", "hover:bg-purple-500")
        btn.classList.add("bg-green-600")
        setTimeout(() => {
          btn.textContent = originalText
          btn.classList.remove("bg-green-600")
          btn.classList.add("bg-purple-600", "hover:bg-purple-500")
          btn.disabled = false
        }, 3000)
      } else {
        btn.textContent = "Enhancement failed"
        btn.classList.remove("opacity-50")
        setTimeout(() => {
          btn.textContent = originalText
          btn.disabled = false
        }, 2000)
      }
    } catch {
      btn.textContent = "Enhancement failed"
      btn.classList.remove("opacity-50")
      setTimeout(() => {
        btn.textContent = originalText
        btn.disabled = false
      }, 2000)
    }
  }

  markPosted() {
    const checked = this.postedCheckboxTarget.checked
    this.postedValue = checked

    if (this.hasPostedStatusTarget) {
      if (checked) {
        this.postedStatusTarget.textContent = "Posted just now"
        this.postedStatusTarget.className = "text-purple-400"
        const prev = this.postedStatusTarget.previousElementSibling
        if (prev && prev.innerHTML === "") prev.innerHTML = "&middot;"
      } else {
        this.postedStatusTarget.textContent = ""
        const prev = this.postedStatusTarget.previousElementSibling
        if (prev) prev.innerHTML = ""
      }
    }

    this.logAction("posted", checked)
  }

  saveText(text) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.logUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
      body: JSON.stringify({ event_url: this.urlValue, action_type: "save_text", text })
    })
  }

  logAction(actionType, posted) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const body = { event_url: this.urlValue, action_type: actionType }
    if (actionType === "posted") body.posted = String(posted)

    fetch(this.logUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
      body: JSON.stringify(body)
    })
  }

  buildPost() {
    const spots = this.spotsValue
    const capacity = this.capacityValue
    let urgencyEmoji = "\u2728"
    let urgency = "Seats are still available \u2014 don\u2019t miss out!"

    if (spots > 0 && capacity > 0) {
      const pctFull = ((capacity - spots) / capacity) * 100
      if (pctFull >= 80) {
        urgencyEmoji = "\uD83D\uDD25"
        urgency = `Only ${spots} spots left! This class is almost full.`
      } else if (pctFull >= 50) {
        urgencyEmoji = "\u23F3"
        urgency = `Spots are filling up \u2014 ${spots} of ${capacity} seats remaining.`
      }
    }

    let lines = [
      `${urgencyEmoji} ${this.nameValue}`,
      "",
      `\uD83D\uDCC5 ${this.dateValue}`,
      `\u23F0 ${this.timeValue}`
    ]

    if (this.priceValue) {
      lines.push(`\uD83D\uDCB2 $${this.priceValue} per person`)
    }

    lines.push(`\uD83D\uDCCD New York Kitchen, Canandaigua`)
    lines.push("")

    if (this.descriptionValue) {
      lines.push(this.descriptionValue)
      lines.push("")
    }

    lines.push(urgency)
    lines.push("")
    lines.push(`\uD83D\uDD17 Link in bio to reserve your spot!`)
    lines.push(this.urlValue)
    lines.push("")
    lines.push("#NewYorkKitchen #FingerLakes #CookingClass #HandsOnCooking #NYKitchen #Canandaigua #FLXFood #DateNight #TeamBuilding #CulinaryExperience")

    return lines.join("\n")
  }
}
