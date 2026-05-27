import { Controller } from "@hotwired/stimulus"
import "chart.js"

// Day-of-week sales chart on the kitchen list page. Renders two bar
// series per weekday: the historical average (gray) and this week's
// actuals (orange). This week's bars only appear for days that have a
// snapshot.
//
// Data shape (JSON in data attrs):
//   data-dow-chart-avg-value="[21.0,16.4,27.0,33.8,36.6,30.4,23.2]"  (Sun..Sat)
//   data-dow-chart-week-value="[7,22,28,18,14,null,null]"
export default class extends Controller {
  static targets = ["canvas"]
  static values  = { avg: Array, week: Array }

  connect() {
    const labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    const Chart  = window.Chart

    const datasets = [
      {
        label: "6-week avg",
        data:  this.avgValue,
        backgroundColor: "rgba(156, 163, 175, 0.4)",  // gray-400 @ 40%
        borderRadius: 4,
        borderSkipped: false,
      }
    ]
    // Only add "This week" if at least one day has a recorded value. With no
    // current-week snapshots yet the series is all-null — drawing it leaves a
    // dangling orange legend and no bars, which reads as broken.
    const hasWeek = Array.isArray(this.weekValue) && this.weekValue.some((v) => v != null)
    if (hasWeek) {
      datasets.push({
        label: "This week",
        data:  this.weekValue,
        backgroundColor: "rgba(234, 88, 12, 0.85)",   // orange-600 @ 85%
        borderRadius: 4,
        borderSkipped: false,
      })
    }

    this.chart = new Chart(this.canvasTarget, {
      type: "bar",
      data: { labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: "bottom",
            labels: { color: "#9ca3af", boxWidth: 12, font: { size: 11 } }
          },
          tooltip: {
            backgroundColor: "rgba(17, 24, 39, 0.95)",
            titleColor: "#fff",
            bodyColor: "#d1d5db",
            borderColor: "#374151",
            borderWidth: 1,
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
