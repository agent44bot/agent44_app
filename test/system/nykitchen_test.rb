require_relative "system_test_helper"

class NykitchenSystemTest < SystemTestCase
  test "kitchen page loads and shows event cards" do
    @page.goto("#{BASE_URL}/nykitchen")

    # Page should load without errors
    assert_equal 200, @page.evaluate("() => window.performance.getEntriesByType('navigation')[0]?.responseStatus || 200")

    # Page should contain NY Kitchen somewhere
    body = @page.text_content("body")
    assert_match(/NY Kitchen/i, body)

    # Should show event cards
    cards = @page.query_selector_all("[data-kitchen-filter-target='card']")
    assert cards.size > 0, "Expected event cards on the page"
  end

  test "filter chips work" do
    @page.goto("#{BASE_URL}/nykitchen")

    # Click the "Available" filter chip
    available_chip = @page.query_selector("[data-filter='instock']")
    if available_chip
      available_chip.click
      sleep 0.3

      # All visible cards should have status=instock
      visible_cards = @page.query_selector_all("[data-kitchen-filter-target='card']:not([style*='display: none'])")
      visible_cards.each do |card|
        status = card.get_attribute("data-status")
        assert_equal "instock", status, "Expected only 'instock' cards after filtering"
      end
    end
  end

  test "preview post panel expands and shows draft text" do
    @page.goto("#{BASE_URL}/nykitchen")

    # Find the first "Preview post" button
    preview_btn = @page.query_selector("[data-action='social-post#toggle']")
    assert preview_btn, "Expected a 'Preview post' button on the page"

    preview_btn.click
    sleep 0.3

    # Preview panel should be visible
    preview = @page.query_selector("[data-social-post-target='preview']:not(.hidden)")
    assert preview, "Expected preview panel to be visible after clicking"

    # Preview text should contain event details
    text = @page.text_content("[data-social-post-target='previewText']")
    assert_match(/New York Kitchen/, text, "Expected 'New York Kitchen' in the draft post")
    assert_match(/#NewYorkKitchen/, text, "Expected hashtags in the draft post")
  end

  test "preview post text is editable" do
    @page.goto("#{BASE_URL}/nykitchen")

    preview_btn = @page.query_selector("[data-action='social-post#toggle']")
    preview_btn&.click
    sleep 0.3

    preview_text = @page.query_selector("[data-social-post-target='previewText']")
    assert preview_text, "Expected preview text element"

    editable = preview_text.get_attribute("contenteditable")
    assert_equal "true", editable, "Expected preview text to be contenteditable"
  end

  test "enhance with AI button exists but is not clicked in tests" do
    @page.goto("#{BASE_URL}/nykitchen")

    preview_btn = @page.query_selector("[data-action='social-post#toggle']")
    preview_btn&.click
    sleep 0.3

    enhance_btn = @page.query_selector("[data-social-post-target='enhanceBtn']")
    assert enhance_btn, "Expected 'Enhance with AI' button in preview panel"
    assert_match(/Enhance with AI/, enhance_btn.text_content)
    # NOTE: We intentionally do NOT click this button to avoid Anthropic API costs
  end

  test "admin kitchen redirects to nykitchen" do
    response = @page.goto("#{BASE_URL}/admin/kitchen")
    # Should redirect to /nykitchen (301)
    assert_equal "#{BASE_URL}/nykitchen", @page.url, "Expected /admin/kitchen to redirect to /nykitchen"
  end

  test "home page loads" do
    @page.goto("#{BASE_URL}/")
    title = @page.title
    assert title.present?, "Expected home page to have a title"
    assert_equal 200, @page.evaluate("() => window.performance.getEntriesByType('navigation')[0]?.responseStatus || 200")
  end

  test "jobs page loads" do
    @page.goto("#{BASE_URL}/jobs")
    assert_equal 200, @page.evaluate("() => window.performance.getEntriesByType('navigation')[0]?.responseStatus || 200")

    # Should have job listings
    heading = @page.text_content("body")
    assert heading.present?, "Expected content on jobs page"
  end
end
