import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleBtn", "preview", "previewText", "copyBtn"]
  static values = {
    name: String,
    date: String,
    time: String,
    price: String,
    spots: Number,
    capacity: Number,
    url: String,
    description: String
  }

  toggle() {
    const panel = this.previewTarget
    const isHidden = panel.classList.contains("hidden")

    if (isHidden) {
      this.previewTextTarget.textContent = this.buildPost()
      panel.classList.remove("hidden")
      this.toggleBtnTarget.textContent = "Hide preview"
    } else {
      panel.classList.add("hidden")
      this.toggleBtnTarget.textContent = "Preview post"
    }
  }

  copy() {
    const post = this.buildPost()
    navigator.clipboard.writeText(post).then(() => {
      const btn = this.copyBtnTarget
      const original = btn.textContent
      btn.textContent = "Copied!"
      btn.classList.remove("bg-blue-600", "hover:bg-blue-500")
      btn.classList.add("bg-green-600")
      setTimeout(() => {
        btn.textContent = original
        btn.classList.remove("bg-green-600")
        btn.classList.add("bg-blue-600", "hover:bg-blue-500")
      }, 2000)
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
