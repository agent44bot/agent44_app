require_relative "system_test_helper"
require_relative "pages/base_page"
require_relative "pages/kitchen_page"

# End-to-end: admin clicks 'Send to Social Agent' on an event row and
# lands on the draft's edit page (/workspaces/:slug/drafts/:id/edit)
# with the draft persisted in draft mode. Catches regressions in any of:
#   - The button rendering (admin? + sendable_workspaces gate in event_card)
#   - The Stimulus social-post controller binding sendToWorkspace
#   - The kitchen_controller#send_to_workspace endpoint
#   - The JSON response shape (workspace_url) the JS uses for the redirect
class HandoffToSocialAgentSystemTest < SystemTestCase
  setup do
    @kitchen = KitchenPage.new(@page, BASE_URL) if @page

    # The seeded test DB is from a pre-workspaces prod snapshot, so we
    # create the state we need explicitly: an admin who owns the NYK
    # workspace, an active social account, a snapshot with events.
    @admin = User.find_or_create_by!(email_address: "handoff-admin@nyk.test") do |u|
      u.role     = "admin"
      u.password = "password123"
    end
    @admin.update!(role: "admin") # in case it existed with a different role
    @ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @admin }
    @ws.memberships.find_or_create_by!(user: @admin) { |m| m.role = "owner" }
    @ws.social_accounts.find_or_create_by!(platform: "x", external_id: "handoff-test") do |a|
      a.handle = "@nyktest"; a.connected_by = @admin
      a.access_token = "AT"; a.refresh_token = "RT"
      a.token_expires_at = 2.hours.from_now; a.status = "active"
    end

    snap = KitchenSnapshot.find_or_create_by!(taken_on: Date.current)
    snap.kitchen_events.find_or_create_by!(url: "https://nykitchen.com/event/handoff-test") do |e|
      e.name = "Whiskey Tasting"; e.start_at = 2.days.from_now.change(hour: 18)
      e.availability = "InStock"; e.spots_left = 5; e.capacity = 10
    end
  end

  test "admin can hand off an event post to the Social Agent" do
    @page.goto("#{BASE_URL}/session/new")
    @page.fill("input[name='email_address']", @admin.email_address)
    @page.fill("input[name='password']",      "password123")
    @page.click("button[type='submit']")
    sleep 0.5

    @kitchen.visit
    @kitchen.expand_first_week

    btn = @kitchen.handoff_button
    assert btn, "Expected 'Send to Social Agent' button on the event row"
    assert_match(/send to social agent/i, btn.text_content)

    test_url = "https://nykitchen.com/event/handoff-test"
    ActiveRecord::Base.connection.clear_query_cache
    refute WorkspaceDraft.where(source_url: test_url).exists?,
           "Pre-condition: no draft for the test event before handoff"

    btn.click
    50.times { break if @page.url =~ %r{/workspaces/nykitchen/drafts/\d+/edit}; sleep 0.1 }

    # The redirect drops Lora directly into the draft's edit page so she
    # can tweak + publish without an intermediate scroll through the
    # composer's drafts list.
    assert_match %r{/workspaces/nykitchen/drafts/\d+/edit}, @page.url,
                 "Expected to land on the draft edit page after handoff, got #{@page.url}"

    # The draft itself was persisted in draft mode.
    ActiveRecord::Base.connection.clear_query_cache
    draft = WorkspaceDraft.find_by(source_url: test_url)
    assert draft, "Expected a WorkspaceDraft for #{test_url} to exist after handoff"
    assert_equal @ws.id,    draft.workspace_id, "Draft should belong to the NYK workspace"
    assert_equal "draft",   draft.status,       "Draft should be in draft mode (not published)"
    assert_match(/Whiskey/, draft.body,         "Draft body should carry the event content forward")

    # And the edit page actually loads the draft body for editing.
    body_text = @page.text_content("body").to_s
    assert_match(/Whiskey/, body_text, "Draft body should be loaded on the edit page")
  end
end
