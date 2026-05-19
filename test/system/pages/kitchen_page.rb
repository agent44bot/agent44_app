require_relative "base_page"

class KitchenPage < BasePage
  def visit
    super("/nykitchen/list")
  end

  def visit_hub
    super("/nykitchen")
  end

  def cards
    page.query_selector_all("[data-kitchen-filter-target='card']")
  end

  def visible_cards
    page.query_selector_all("[data-kitchen-filter-target='card']:not(.hidden)")
  end

  def filter_chip(status)
    page.query_selector("[data-filter-status='#{status}']")
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

  def save_button
    page.query_selector("[data-social-post-target='saveBtn']")
  end

  def enhance_button
    page.query_selector("[data-social-post-target='enhanceBtn']")
  end

  def open_preview
    preview_button&.click
    sleep 0.3
  end

  # The filter chips and week sections start collapsed; tests that interact
  # with their contents must expand first.
  def expand_filter
    page.query_selector("[data-nyk-filter-tracker-url-value] > button")&.click
    sleep 0.2
  end

  def expand_first_week
    page.query_selector("[data-kitchen-filter-target='section'] > button")&.click
    sleep 0.2
  end

  def handoff_button
    page.query_selector("[data-social-post-target='sendToWorkspaceBtn']")
  end
end
