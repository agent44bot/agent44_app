import { Controller } from "@hotwired/stimulus"
import "chart.js"

// Single-series "tickets sold" bar chart on the kitchen Analyst page. Drives
// the week/month historical chart from one canvas: a toggle swaps the dataset
// in place (chart.update) rather than mounting a second chart in a hidden
// canvas, which avoids Chart.js's zero-size-on-hidden resize bug.
//
// Tickets are observed sales (day-over-day spots_left drops, summed per
// bucket), so the first tracked bucket reads low.
//
// Preferred (multi-series) shape — JSON array in a data attr:
//   data-sales-bar-chart-series-value='[
//     {"key":"week","label":"Week","tooltipPrefix":"Week of ","caption":"…","labels":[…],"values":[…]},
//     {"key":"month","label":"Month","tooltipPrefix":"","caption":"…","labels":[…],"values":[…]}
//   ]'
// Toggle buttons: data-sales-bar-chart-target="toggle" + data-action="sales-bar-chart#select"
//                 + data-sales-bar-chart-index-param="0"
//
// Legacy single-series shape (still supported): labels-value + values-value
// + optional tooltip-prefix-value.
export default class extends Controller {
  static targets = ["canvas", "toggle", "caption"]
  static values = {
    labels:        Array,
    values:        Array,
    tooltipPrefix: { type: String, default: "" },
    series:        { type: Array, default: [] }
  }

  connect() {
    this.series = (this.seriesValue && this.seriesValue.length)
      ? this.seriesValue
      : [ { label: "", tooltipPrefix: this.tooltipPrefixValue, caption: "",
            labels: this.labelsValue, values: this.valuesValue } ]
    this.activeIndex = 0

    const self  = this
    const first = this.series[0]

    this.chart = new window.Chart(this.canvasTarget, {
      type: "bar",
      data: {
        labels: first.labels,
        datasets: [ {
          label: "Tickets sold",
          data:  first.values,
          backgroundColor: "rgba(234, 88, 12, 0.85)",   // orange-600 @ 85%
          borderRadius: 4,
          borderSkipped: false,
        } ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            backgroundColor: "rgba(17, 24, 39, 0.95)",
            titleColor: "#fff",
            bodyColor: "#d1d5db",
            borderColor: "#374151",
            borderWidth: 1,
            callbacks: {
              title: (items) => `${self.series[self.activeIndex].tooltipPrefix || ""}${items[0].label}`,
              label: (item)  => `${item.parsed.y} tickets sold`,
            }
          }
        },
        scales: {
          x: { grid: { display: false }, ticks: { color: "#9ca3af" } },
          y: { beginAtZero: true, grid: { color: "rgba(75, 85, 99, 0.2)" }, ticks: { color: "#9ca3af", precision: 0 } }
        }
      }
    })

    this.#sync()
  }

  select(event) {
    const i = parseInt(event.params.index, 10)
    if (Number.isNaN(i) || i === this.activeIndex || !this.series[i]) return
    this.activeIndex = i
    this.chart.data.labels        = this.series[i].labels
    this.chart.data.datasets[0].data = this.series[i].values
    this.chart.update()
    this.#sync()
  }

  // Reflect the active series in the toggle buttons + caption.
  #sync() {
    this.toggleTargets.forEach((btn, i) => {
      const on = i === this.activeIndex
      btn.classList.toggle("bg-gray-700", on)
      btn.classList.toggle("text-white", on)
      btn.classList.toggle("text-gray-400", !on)
    })
    if (this.hasCaptionTarget) {
      this.captionTarget.textContent = this.series[this.activeIndex].caption || ""
    }
  }

  disconnect() {
    this.chart?.destroy()
  }
}
