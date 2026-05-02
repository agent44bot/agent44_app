import { Controller } from "@hotwired/stimulus"

const SVG_NS = "http://www.w3.org/2000/svg"

const STRAND_ENDS = [
  [198, 27.8],
  [185.4, 75],
  [157.6, 123.2],
  [123.2, 157.6],
  [75, 185.4],
  [27.8, 198]
]

const TRAVEL_MS = 8000
const FADE_MS = 700
const AMBER = "#fb923c"
const EMERALD = "#34d399"

export default class extends Controller {
  static targets = ["host"]

  connect() {
    this.bubbles = new Map()
    this.strandsInUse = new Set()
  }

  spawn(id) {
    if (this.bubbles.has(id)) return
    const strand = this._pickStrand()
    const [endX, endY] = STRAND_ENDS[strand]

    const circle = document.createElementNS(SVG_NS, "circle")
    circle.setAttribute("cx", "0")
    circle.setAttribute("cy", "0")
    circle.setAttribute("r", "1.4")
    circle.setAttribute("fill", AMBER)
    circle.setAttribute("opacity", "0.95")
    circle.setAttribute("data-strand", String(strand))

    const animateX = this._buildAnimate("cx", endX)
    const animateY = this._buildAnimate("cy", endY)
    circle.appendChild(animateX)
    circle.appendChild(animateY)

    this.hostTarget.appendChild(circle)

    // Kick the animations now (begin="indefinite" + beginElement is the only
    // reliable way to start SMIL on dynamically-inserted nodes).
    try { animateX.beginElement() } catch (_) {}
    try { animateY.beginElement() } catch (_) {}

    this.strandsInUse.add(strand)
    this.bubbles.set(id, { circle, strand })
  }

  complete(id) {
    const entry = this.bubbles.get(id)
    if (!entry) return
    const { circle, strand } = entry
    this.bubbles.delete(id)

    circle.setAttribute("fill", EMERALD)

    const fade = document.createElementNS(SVG_NS, "animate")
    fade.setAttribute("attributeName", "opacity")
    fade.setAttribute("from", "0.95")
    fade.setAttribute("to", "0")
    fade.setAttribute("dur", `${FADE_MS}ms`)
    fade.setAttribute("fill", "freeze")
    fade.setAttribute("begin", "indefinite")
    circle.appendChild(fade)
    try { fade.beginElement() } catch (_) {}

    setTimeout(() => {
      circle.remove()
      this.strandsInUse.delete(strand)
    }, FADE_MS)
  }

  _buildAnimate(attr, to) {
    const el = document.createElementNS(SVG_NS, "animate")
    el.setAttribute("attributeName", attr)
    el.setAttribute("from", "0")
    el.setAttribute("to", String(to))
    el.setAttribute("dur", `${TRAVEL_MS}ms`)
    el.setAttribute("fill", "freeze")
    el.setAttribute("begin", "indefinite")
    return el
  }

  _pickStrand() {
    const free = STRAND_ENDS.map((_, i) => i).filter(i => !this.strandsInUse.has(i))
    if (free.length === 0) return Math.floor(Math.random() * STRAND_ENDS.length)
    return free[Math.floor(Math.random() * free.length)]
  }
}
