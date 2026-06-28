import { Controller } from "@hotwired/stimulus"

// Click a column header to sort the table by that column; click again to flip
// direction. Numeric columns (Calls, Cost, Avg/call) sort by a data-sort-value
// attribute on the cell so we order by the real number, not the formatted "$"
// string. Sorting is purely client-side reordering of <tbody> rows; a <tfoot>
// (e.g. the Total row) is left in place. Headers opt in with
// data-action="click->table-sort#sort" and data-sort-type="number|text".
export default class extends Controller {
  sort(event) {
    const th = event.currentTarget
    const headers = Array.from(th.parentElement.children)
    const index = headers.indexOf(th)
    const type = th.dataset.sortType || "text"

    // Toggle direction when re-clicking the same column, else default ascending.
    const asc = this.sortedIndex === index ? !this.asc : true
    this.sortedIndex = index
    this.asc = asc

    const tbody = this.element.tBodies[0]
    const rows = Array.from(tbody.rows)
    rows.sort((a, b) => {
      const x = this.value(a.cells[index], type)
      const y = this.value(b.cells[index], type)
      const cmp = type === "number" ? x - y : String(x).localeCompare(String(y))
      return asc ? cmp : -cmp
    })
    rows.forEach((row) => tbody.appendChild(row))

    headers.forEach((h) => h.querySelector("[data-sort-arrow]")?.replaceChildren())
    const arrow = th.querySelector("[data-sort-arrow]")
    if (arrow) arrow.textContent = asc ? " ↑" : " ↓"
  }

  value(cell, type) {
    if (!cell) return type === "number" ? 0 : ""
    if (type === "number") {
      const raw = cell.dataset.sortValue ?? cell.textContent.replace(/[^0-9.\-]/g, "")
      return parseFloat(raw) || 0
    }
    return cell.textContent.trim().toLowerCase()
  }
}
