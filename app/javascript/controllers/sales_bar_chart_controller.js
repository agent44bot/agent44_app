import { Controller } from "@hotwired/stimulus"
import "chart.js"

// Generic single-series "tickets sold" bar chart on the kitchen list page.
// Drives both the by-week and by-month historical charts — same orange bars,
// only the buckets and tooltip title differ. Tickets are observed sales
// (day-over-day spots_left drops, summed per bucket), so the first tracked
// bucket reads low.
//
// Data shape (JSON in data attrs):
//   data-sales-bar-chart-labels-value='["Apr 19","Apr 26","May 3"]'
//   data-sales-bar-chart-values-value="[154,233,188]"
//   data-sales-bar-chart-tooltip-prefix-value="Week of "   (optional)
export default class extends Controller {
  static targets = ["canvas"]
  static values  = { labels: Array, values: Array, tooltipPrefix: { type: String, default: "" } }

  connect() {
    const Chart  = window.Chart
    const prefix = this.tooltipPrefixValue

    this.chart = new Chart(this.canvasTarget, {
      type: "bar",
      data: {
        labels: this.labelsValue,
        datasets: [
          {
            label: "Tickets sold",
            data:  this.valuesValue,
            backgroundColor: "rgba(234, 88, 12, 0.85)",   // orange-600 @ 85%
            borderRadius: 4,
            borderSkipped: false,
          }
        ]
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
              title: (items) => `${prefix}${items[0].label}`,
              label: (item) => `${item.parsed.y} tickets sold`,
            }
          }
        },
        scales: {
          x: {
            grid: { display: false },
            ticks: { color: "#9ca3af" }
          },
          y: {
            beginAtZero: true,
            grid:  { color: "rgba(75, 85, 99, 0.2)" },
            ticks: { color: "#9ca3af", precision: 0 }
          }
        }
      }
    })
  }

  disconnect() {
    this.chart?.destroy()
  }
}
