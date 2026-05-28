import { Controller } from "@hotwired/stimulus"
import "chart.js"

// Per-card jobs trend line chart on /jobs (Traditional / AI-Augmented / Agent
// Engineer). This lives in a Stimulus controller rather than an inline <script>
// on purpose: a nonce'd inline <script> is blocked by CSP when Turbo re-injects
// it during an in-app (Turbo Drive) visit, so the charts rendered only on a hard
// reload and came up blank when you navigated to /jobs from elsewhere in the
// app. Stimulus connect() re-runs on every Turbo visit and module code isn't
// subject to the inline-script CSP block, so the charts render every time.
//
// Data (JSON in data attrs on the <canvas>):
//   data-jobs-trend-chart-points-value="[6,3,...]"
//   data-jobs-trend-chart-labels-value='["Apr 28",...]'
//   data-jobs-trend-chart-color-value="rgb(249,115,22)"
//   data-jobs-trend-chart-max-value="56"   (shared y-axis ceiling; 0 = auto)
export default class extends Controller {
  static values = { points: Array, labels: Array, color: String, max: Number }

  connect() {
    const Chart = window.Chart
    const data  = this.pointsValue
    const color = this.colorValue
    const info  = this.#trendInfo(data)

    this.chart = new Chart(this.element, {
      type: "line",
      data: {
        labels: this.labelsValue,
        datasets: [{
          label: "Jobs posted",
          data,
          borderColor: color,
          backgroundColor: color.replace("rgb", "rgba").replace(")", ",0.1)"),
          fill: true, tension: 0.3, pointRadius: 2, pointHoverRadius: 5
        }]
      },
      options: {
        responsive: true,
        plugins: {
          legend: { display: false },
          tooltip: { callbacks: { label: (item) => item.raw + " jobs posted" } }
        },
        scales: {
          // max:0 (every series empty) would flatten the line, so fall back to
          // Chart.js auto-scaling in that case.
          y: { beginAtZero: true, max: this.maxValue || undefined, ticks: { precision: 0, color: "#9ca3af" }, grid: { color: "#1f2937" } },
          x: { ticks: { maxTicksLimit: 8, color: "#9ca3af" }, grid: { color: "#1f2937" } }
        }
      }
    })

    this.summary = this.#buildSummary(info)
    this.element.parentNode.appendChild(this.summary)
  }

  disconnect() {
    this.chart?.destroy()
    this.summary?.remove()
  }

  #trendInfo(data) {
    const total = data.reduce((a, b) => a + b, 0)
    const mid = Math.floor(data.length / 2)
    const firstHalf = data.slice(0, mid).reduce((a, b) => a + b, 0)
    const secondHalf = data.slice(mid).reduce((a, b) => a + b, 0)
    const trending = secondHalf > firstHalf ? "up" : secondHalf < firstHalf ? "down" : "flat"
    const pct = firstHalf > 0 ? Math.round(Math.abs(secondHalf - firstHalf) / firstHalf * 100) : 0
    return { total, trending, pct }
  }

  #buildSummary(info) {
    const arrow = info.trending === "up" ? "▲" : info.trending === "down" ? "▼" : "▶"
    const cls = info.trending === "up" ? "text-green-600" : info.trending === "down" ? "text-red-500" : "text-gray-500"
    const word = info.trending === "up" ? "increase" : info.trending === "down" ? "decrease" : "no change"
    const el = document.createElement("div")
    el.className = "trend-summary mt-3 flex items-center gap-2 text-sm"
    el.innerHTML = `<span class="font-semibold ${cls}">${arrow} ${info.pct}% ${word}</span><span class="text-gray-400">vs prev 15 days (${info.total} total)</span>`
    return el
  }
}
