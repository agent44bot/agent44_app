require "test_helper"

class SocialLeadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "slc-o-#{SecureRandom.hex(4)}@example.com")
    @ws = Workspace.create!(name: "SLC WS", slug: "slc-#{SecureRandom.hex(4)}", owner: @owner)
    @lead = @ws.social_leads.create!(platform: "bluesky", external_id: "at://x", text: "hi",
                                     status: "new", draft_reply: "hey")
  end

  test "the Echo page renders a Conversations section with the lead + drafted reply" do
    sign_in_as(@owner)
    get social_workspace_path(@ws.slug)
    assert_response :success
    assert_includes @response.body, "Conversations"
    assert_includes @response.body, "hi"  # the post text
    assert_includes @response.body, "hey" # the drafted reply
  end

  test "a manager saves listening topics from the Echo page; they drive the job queries" do
    Setting.set("social_listen:slugs", @ws.slug)
    sign_in_as(@owner)
    get social_workspace_path(@ws.slug)
    assert_includes @response.body, "Listening topics", "manager sees the topics editor when listening is on"
    patch listening_topics_workspace_path(@ws.slug), params: { queries: "wine tasting\nbeer tasting" }
    assert_equal [ "wine tasting", "beer tasting" ], SocialListenJob.queries_for(@ws)
  end

  test "a non-manager cannot change listening topics" do
    viewer = User.create!(email_address: "lt-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: viewer, role: "viewer")
    sign_in_as(viewer)
    patch listening_topics_workspace_path(@ws.slug), params: { queries: "hacked" }
    assert_not_equal [ "hacked" ], SocialListenJob.queries_for(@ws)
  end

  test "a writer can dismiss a lead" do
    sign_in_as(@owner)
    patch dismiss_workspace_social_lead_path(workspace_slug: @ws.slug, id: @lead.id)
    assert_equal "dismissed", @lead.reload.status
  end

  test "mark_sent stores the edited reply and flips status" do
    sign_in_as(@owner)
    patch mark_sent_workspace_social_lead_path(workspace_slug: @ws.slug, id: @lead.id),
          params: { draft_reply: "edited reply" }
    @lead.reload
    assert_equal "sent", @lead.status
    assert_equal "edited reply", @lead.draft_reply
  end

  test "a viewer (member but not a writer) is forbidden and the lead is unchanged" do
    viewer = User.create!(email_address: "slc-v-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: viewer, role: "viewer")
    sign_in_as(viewer)
    patch dismiss_workspace_social_lead_path(workspace_slug: @ws.slug, id: @lead.id)
    assert_response :forbidden
    assert_equal "new", @lead.reload.status
  end

  test "a non-member cannot reach another workspace's lead" do
    outsider = User.create!(email_address: "slc-x-#{SecureRandom.hex(4)}@example.com")
    sign_in_as(outsider)
    patch dismiss_workspace_social_lead_path(workspace_slug: @ws.slug, id: @lead.id)
    assert_not_equal "dismissed", @lead.reload.status
    assert_includes [ 404, 302 ], response.status
  end
end
