require_relative "system_test_helper"
require_relative "pages/base_page"
require_relative "pages/kitchen_page"

class NykitchenSystemTest < SystemTestCase
  setup do
    @kitchen = KitchenPage.new(@page, BASE_URL) if @page
  end

  test "kitchen page loads and shows event cards" do
    @kitchen.visit

    assert_equal 200, @kitchen.response_status
    assert_match(/NY Kitchen/i, @kitchen.body_text)
    assert @kitchen.cards.size > 0, "Expected event cards on the page"
  end

  test "filter chips work" do
    @kitchen.visit

    chip = @kitchen.filter_chip("instock")
    assert chip, "Expected 'Available' filter chip on the page"

    chip.click
    sleep 0.3

    @kitchen.visible_cards.each do |card|
      assert_equal "instock", card.get_attribute("data-status"),
        "Expected only 'instock' cards after filtering"
    end
  end

  test "preview post panel expands and shows draft text" do
    @kitchen.visit
    @kitchen.open_preview

    assert @kitchen.preview_panel, "Expected preview panel to be visible"
    assert_match(/New York Kitchen/, @kitchen.preview_text)
    assert_match(/#NewYorkKitchen/, @kitchen.preview_text)
  end

  test "preview post text is editable" do
    @kitchen.visit
    @kitchen.open_preview

    el = @kitchen.preview_text_element
    assert el, "Expected preview text element"
    assert_equal "true", el.get_attribute("contenteditable")
  end

  test "enhance with AI button exists but is not clicked in tests" do
    @kitchen.visit
    @kitchen.open_preview

    btn = @kitchen.enhance_button
    assert btn, "Expected 'Enhance with AI' button in preview panel"
    assert_match(/Enhance with AI/, btn.text_content)
    # NOTE: We intentionally do NOT click this button to avoid Anthropic API costs
  end

  test "admin kitchen redirects to nykitchen" do
    @page.goto("#{BASE_URL}/admin/kitchen")
    assert_equal "#{BASE_URL}/nykitchen", @page.url
  end

  test "home page loads" do
    home = BasePage.new(@page, BASE_URL)
    home.visit("/")
    assert_equal 200, home.response_status
    assert home.title.present?, "Expected home page to have a title"
  end

  test "jobs page loads" do
    jobs = BasePage.new(@page, BASE_URL)
    jobs.visit("/jobs")
    assert_equal 200, jobs.response_status
    assert jobs.body_text.present?, "Expected content on jobs page"
  end
end
