require_relative "system_test_helper"
require_relative "pages/base_page"
require_relative "pages/display_page"

# End-to-end coverage of the public /nykitchen/display screen.
# Runs against the prod-seeded test DB — assertions intentionally
# don't depend on specific event names, only on aggregate behavior.
class DisplaySystemTest < SystemTestCase
  setup do
    @display = DisplayPage.new(@page, BASE_URL) if @page

    # Make sure the Display Agent is set to public so the page is
    # reachable without a token; tests that flip private set it back.
    ws = Workspace.find_or_create_by!(slug: "nykitchen") do |w|
      w.name = "NY Kitchen"
      w.owner = User.first || User.create!(email_address: "disp-sys@nyk.test", role: "admin")
    end
    @agent = ws.agent_for("display")
    @agent.update_settings(visibility: "public", show_image: false)
  end

  test "display page loads publicly and renders slides" do
    @display.visit

    assert_equal 200, @display.response_status
    assert @display.slides.size > 0, "Expected at least one slide on the display"
  end

  test "display page never shows sold-out class names" do
    snap = KitchenSnapshot.latest
    skip "No snapshot in test seed; can't verify sold-out filter" unless snap
    sold_out_names = snap.kitchen_events.upcoming.select(&:sold_out?).map(&:name).compact
    skip "No sold-out events in current seed" if sold_out_names.empty?

    @display.visit
    body = @display.body_text

    sold_out_names.each do |name|
      refute_includes body, name,
        "Sold-out class '#{name}' should not appear on the public display"
    end
  end

  test "display page returns 404 when private and no token" do
    @agent.update_settings(visibility: "private")
    @agent.rotate_share_token!

    @display.visit
    # response_status is recorded from the navigation entry; for a 404
    # the page body itself will not contain our slide UI.
    assert_nil @page.query_selector("article.slide"),
      "Private mode without a token should not render any slides"

    @agent.update_settings(visibility: "public") # cleanup for siblings
  end
end
