require_relative "system_test_helper"

class NykitchenSystemTest < SystemTestCase
  private

  def visit(path)
    @page.goto("#{BASE_URL}#{path}")
  end

  def visit_kitchen
    visit("/nykitchen")
  end

  def open_first_preview
    visit_kitchen
    btn = @page.query_selector("[data-action='social-post#toggle']")
    assert btn, "Expected a 'Preview post' button on the page"
    btn.click
    sleep 0.3
  end

  def assert_page_ok
    assert_equal 200, @page.evaluate("() => window.performance.getEntriesByType('navigation')[0]?.responseStatus || 200")
  end

  public

  test "kitchen page loads and shows event cards" do
    visit_kitchen
    assert_page_ok

    body = @page.text_content("body")
    assert_match(/NY Kitchen/i, body)

    cards = @page.query_selector_all("[data-kitchen-filter-target='card']")
    assert cards.size > 0, "Expected event cards on the page"
  end

  test "filter chips work" do
    visit_kitchen

    available_chip = @page.query_selector("[data-filter='instock']")
    if available_chip
      available_chip.click
      sleep 0.3

      visible_cards = @page.query_selector_all("[data-kitchen-filter-target='card']:not([style*='display: none'])")
      visible_cards.each do |card|
        status = card.get_attribute("data-status")
        assert_equal "instock", status, "Expected only 'instock' cards after filtering"
      end
    end
  end

  test "preview post panel expands and shows draft text" do
    open_first_preview

    preview = @page.query_selector("[data-social-post-target='preview']:not(.hidden)")
    assert preview, "Expected preview panel to be visible after clicking"

    text = @page.text_content("[data-social-post-target='previewText']")
    assert_match(/New York Kitchen/, text, "Expected 'New York Kitchen' in the draft post")
    assert_match(/#NewYorkKitchen/, text, "Expected hashtags in the draft post")
  end

  test "preview post text is editable" do
    open_first_preview

    preview_text = @page.query_selector("[data-social-post-target='previewText']")
    assert preview_text, "Expected preview text element"

    editable = preview_text.get_attribute("contenteditable")
    assert_equal "true", editable, "Expected preview text to be contenteditable"
  end

  test "enhance with AI button exists but is not clicked in tests" do
    open_first_preview

    enhance_btn = @page.query_selector("[data-social-post-target='enhanceBtn']")
    assert enhance_btn, "Expected 'Enhance with AI' button in preview panel"
    assert_match(/Enhance with AI/, enhance_btn.text_content)
    # NOTE: We intentionally do NOT click this button to avoid Anthropic API costs
  end

  test "admin kitchen redirects to nykitchen" do
    visit("/admin/kitchen")
    assert_equal "#{BASE_URL}/nykitchen", @page.url, "Expected /admin/kitchen to redirect to /nykitchen"
  end

  test "home page loads" do
    visit("/")
    assert_page_ok
    assert @page.title.present?, "Expected home page to have a title"
  end

  test "jobs page loads" do
    visit("/jobs")
    assert_page_ok
    assert @page.text_content("body").present?, "Expected content on jobs page"
  end
end
