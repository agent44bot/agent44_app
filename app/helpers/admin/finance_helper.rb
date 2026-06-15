module Admin
  module FinanceHelper
    # A clickable column header for the expense line-items table. Links back to
    # the finance page preserving the year, switching the sort to `key`, and
    # toggling the direction when the column is already active. Shows an up/down
    # arrow on the active column. `align` mirrors the cell's text alignment so
    # the arrow sits next to the label, not adrift.
    def expense_sort_header(label, key, year:, current_sort:, current_dir:, align: "left")
      active   = current_sort == key
      next_dir = (active && current_dir == "asc") ? "desc" : "asc"
      arrow    = active ? (current_dir == "asc" ? "↑" : "↓") : ""
      justify  = { "right" => "justify-end", "center" => "justify-center" }.fetch(align, "justify-start")

      link_to admin_finance_path(year: year, sort: key, dir: next_dir),
              class: "flex items-center gap-1 #{justify} hover:text-gray-300 #{'text-gray-300' if active}".strip do
        safe_join([ label, content_tag(:span, arrow, class: "text-[10px] leading-none") ])
      end
    end
  end
end
