require_relative "base_page"

class KitchenPage < BasePage
  def visit
    super("/nykitchen")
  end

  def cards
    page.query_selector_all("[data-kitchen-filter-target='card']")
  end

  def visible_cards
    page.query_selector_all("[data-kitchen-filter-target='card']:not([style*='display: none'])")
  end

  def filter_chip(status)
    page.query_selector("[data-filter='#{status}']")
  end

  def preview_button
    page.query_selector("[data-action='social-post#toggle']")
  end

  def preview_panel
    page.query_selector("[data-social-post-target='preview']:not(.hidden)")
  end

  def preview_text_element
    page.query_selector("[data-social-post-target='previewText']")
  end

  def preview_text
    page.text_content("[data-social-post-target='previewText']")
  end

  def enhance_button
    page.query_selector("[data-social-post-target='enhanceBtn']")
  end

  def open_preview
    preview_button&.click
    sleep 0.3
  end
end
