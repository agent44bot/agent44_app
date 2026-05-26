require "test_helper"

class KitchenControllerTest < ActionDispatch::IntegrationTest
  setup do
    @today = Date.today
    @snapshot = KitchenSnapshot.create!(taken_on: @today)
    # Most tests visit /nykitchen/{list,test,data,digests} which require
    # auth. Default to a signed-in admin so tests can focus on the page
    # behavior; tests covering the auth gate or specific roles sign in
    # their own user explicitly.
    @default_user = User.create!(email_address: "kctrl-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@default_user)
  end

  test "week headers show availability bar with red and green only" do
    # Create events this week: 2 available, 1 sold out, 1 limited
    # Limited rolls into "available" for the binary bar.
    this_week = 2.days.from_now
    create_event("Pasta 101", this_week, "InStock")
    create_event("Wine 201", this_week + 1.hour, "InStock")
    create_event("Cheese Class", this_week + 2.hours, "SoldOut")
    create_event("Baking Basics", this_week + 3.hours, "Limited")

    get nyk_list_path
    assert_response :success

    assert_select "div.bg-red-500"
    assert_select "div.bg-green-500"
    assert_select "div.bg-amber-500", count: 0, message: "Limited segments removed — bar is binary now"
  end

  test "week with all available events shows only green bar" do
    next_monday = @today + ((7 - @today.cwday) % 7) + 1
    create_event("Event A", next_monday.to_time + 10.hours, "InStock")
    create_event("Event B", next_monday.to_time + 14.hours, "InStock")

    get nyk_list_path
    assert_response :success

    # Find the week section containing these events
    assert_select "section[id^='week-']" do |sections|
      next_week_section = sections.find { |s| s.text.include?("Event A") }
      assert next_week_section, "Expected a week section containing the events"
      assert_select next_week_section, "div.bg-green-500"
      assert_select next_week_section, "div.bg-red-500", count: 0
      assert_select next_week_section, "div.bg-amber-500", count: 0
    end
  end

  test "week with all sold out events shows only red bar" do
    next_monday = @today + ((7 - @today.cwday) % 7) + 1
    create_event("Sold A", next_monday.to_time + 10.hours, "SoldOut")
    create_event("Sold B", next_monday.to_time + 14.hours, "SoldOut")
    create_event("Closed C", next_monday.to_time + 16.hours, "Closed")

    get nyk_list_path
    assert_response :success

    assert_select "section[id^='week-']" do |sections|
      section = sections.find { |s| s.text.include?("Sold A") }
      assert section, "Expected a week section with sold out events"
      assert_select section, "div.bg-red-500"
      assert_select section, "div.bg-green-500", count: 0
    end
  end

  test "availability bar percentages reflect event counts" do
    # 3 events: 1 sold out (33.3%), 2 available (66.7%)
    this_week = 2.days.from_now
    create_event("Available 1", this_week, "InStock")
    create_event("Available 2", this_week + 1.hour, "InStock")
    create_event("Gone", this_week + 2.hours, "SoldOut")

    get nyk_list_path
    assert_response :success

    assert_select "div.bg-red-500[title='1 sold out / closed']"
    assert_select "div.bg-green-500[title='2 available']"
  end

  test "events with empty availability are excluded from the bar (red + green only)" do
    # The bar + percentage are now driven by sold + available only;
    # "unknown" events don't render any segment.
    this_week = 2.days.from_now
    create_event("Sold Out Class", this_week, "SoldOut")
    create_event("Private Event", this_week + 1.hour, "")  # empty = "other"

    get nyk_list_path
    assert_response :success

    assert_select "section[id^='week-']" do |sections|
      section = sections.find { |s| s.text.include?("Private Event") }
      assert section
      assert_select section, "div.bg-gray-500", count: 0, message: "Gray unknown segment removed"
      assert_select section, "div.bg-amber-500", count: 0, message: "Amber limited segment removed"
      assert_select section, "div.bg-red-500[title='1 sold out / closed']"
    end
  end

  test "each week section has an id for deep linking" do
    # Pin to a Tuesday so week 0 spans Tue–Sun and week 1 starts the next
    # Monday. Otherwise late-week runs (e.g. Saturday) push 2.days.from_now
    # past Sunday, leaving week 0 empty and the view skipping its section.
    travel_to Time.zone.local(2026, 6, 16, 9, 0) do
      create_event("This Week Event", 1.day.from_now, "InStock")
      create_event("Next Week Event", 7.days.from_now, "InStock")

      get nyk_list_path
      assert_response :success

      assert_select "section#week-0"
      assert_select "section#week-1"
    end
  end

  test "digest summary page renders totals and per-event old → new spots" do
    digest = @snapshot.kitchen_ticket_digests.create!(
      total_tickets: 5,
      sold_out_count: 1,
      change_count: 2,
      entries: [
        { url: "https://nykitchen.com/events/pasta", name: "Pasta Making",
          start_at: 3.days.from_now.iso8601, instructor: "Chef Lora", price: "85",
          old_spots: 4, new_spots: 0, tickets_bought: 4, sold_out: true,
          week_index: 0, week_label: "Current Week" },
        { url: "https://nykitchen.com/events/wine", name: "Wine Tasting",
          start_at: 10.days.from_now.iso8601, instructor: nil, price: nil,
          old_spots: 12, new_spots: 11, tickets_bought: 1, sold_out: false,
          week_index: 1, week_label: "Next Week" }
      ]
    )

    get nyk_digest_path(digest)
    assert_response :success

    # Stat tiles
    assert_match(/5/, response.body)   # tickets total
    assert_match(/2/, response.body)   # change count
    assert_match(/1/, response.body)   # sold out count

    # Week sections
    assert_match("Current Week", response.body)
    assert_match("Next Week", response.body)

    # Per-event details
    assert_match("Pasta Making", response.body)
    assert_match("Wine Tasting", response.body)
    assert_match(/4 .*?→.*?0/m, response.body)
    assert_match(/12 .*?→.*?11/m, response.body)
    assert_match("SOLD OUT", response.body)
  end

  test "digest summary page returns 404 for unknown id" do
    get nyk_digest_path(id: 999_999)
    assert_response :not_found
  end

  test "index renders Drafted/Posted badges from workspace_status_by_url" do
    admin = User.create!(email_address: "snd-b-#{SecureRandom.hex(4)}@example.com", role: "admin")
    ws    = Workspace.create!(name: "NY Kitchen", owner: admin)
    acct  = ws.social_accounts.create!(platform: "x", connected_by: admin, handle: "@a44",
      external_id: SecureRandom.hex(4), access_token: "AT", refresh_token: "RT",
      token_expires_at: 2.hours.from_now, status: "active")
    drafted_event = create_event("Pasta 101", 2.days.from_now, "InStock")
    posted_event  = create_event("Bread 201", 3.days.from_now, "InStock")

    # Drafted (no posts yet)
    ws.workspace_drafts.create!(author: admin, body: "draft body",
      target_platforms: %w[x], source_url: drafted_event.url)
    # Posted
    ws.workspace_posts.create!(author: admin, social_account: acct, platform: "x",
      body: "posted body", source_url: posted_event.url,
      status: "posted", remote_id: "1", posted_at: 30.minutes.ago)

    sign_in_as(admin)
    get nyk_list_path
    assert_response :success

    assert_match /✓ Drafted/, response.body
    assert_match /✓ Posted/,  response.body
  end

  test "non-admin doesn't see drafted/posted badges (workspace_status preload is admin-only)" do
    admin = User.create!(email_address: "snd-c-#{SecureRandom.hex(4)}@example.com", role: "admin")
    ws    = Workspace.create!(name: "NY Kitchen", owner: admin)
    acct  = ws.social_accounts.create!(platform: "x", connected_by: admin, handle: "@a44",
      external_id: SecureRandom.hex(4), access_token: "AT", refresh_token: "RT",
      token_expires_at: 2.hours.from_now, status: "active")
    event = create_event("Pasta 101", 2.days.from_now, "InStock")
    ws.workspace_drafts.create!(author: admin, body: "draft body",
      target_platforms: %w[x], source_url: event.url)

    laura = User.create!(email_address: "snd-l-#{SecureRandom.hex(4)}@example.com", role: "user")
    sign_in_as(laura)
    get nyk_list_path
    assert_response :success
    refute_match /✓ Drafted/, response.body
    refute_match /✓ Posted/,  response.body
  end

  test "send_to_workspace creates a WorkspaceDraft on the picked workspace" do
    admin = User.create!(email_address: "snd-a-#{SecureRandom.hex(4)}@example.com", role: "admin")
    ws = Workspace.create!(name: "NY Kitchen", owner: admin)
    ws.social_accounts.create!(platform: "x", connected_by: admin, handle: "@a44",
      external_id: SecureRandom.hex(4), access_token: "AT", refresh_token: "RT",
      token_expires_at: 2.hours.from_now, status: "active")
    sign_in_as(admin)

    assert_difference -> { WorkspaceDraft.count }, 1 do
      post "/nykitchen/send_to_workspace",
           params: { text: "Chef's Table Sat 6pm — 1 seat left", event_url: "https://nykitchen.com/event/x", workspace_slug: ws.slug }
    end
    body = JSON.parse(response.body)
    assert body["ok"]
    draft = WorkspaceDraft.last
    assert_equal "/workspaces/#{ws.slug}/drafts/#{draft.id}/edit", body["workspace_url"]
    assert_equal "NY Kitchen",              body["workspace_name"]

    draft = WorkspaceDraft.last
    assert_equal "Chef's Table Sat 6pm — 1 seat left", draft.body
    assert_equal %w[x], draft.target_platforms
    assert_equal "draft", draft.status
  end

  test "send_to_workspace returns the draft's edit URL for the NYK workspace" do
    admin = User.create!(email_address: "snd-nyk-#{SecureRandom.hex(4)}@example.com", role: "admin")
    ws    = Workspace.create!(name: "NYK", owner: admin, slug: "nykitchen")
    ws.social_accounts.create!(platform: "x", connected_by: admin, handle: "@nyk", external_id: SecureRandom.hex(4),
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now, status: "active")
    sign_in_as(admin)

    post "/nykitchen/send_to_workspace",
         params: { text: "hi", event_url: "https://nykitchen.com/event/y", workspace_slug: "nykitchen" }
    draft = WorkspaceDraft.last
    assert_equal "/workspaces/nykitchen/drafts/#{draft.id}/edit",
                 JSON.parse(response.body)["workspace_url"]
  end

  test "send_to_workspace rejects unauthenticated requests" do
    sign_out
    post "/nykitchen/send_to_workspace", params: { text: "hi", workspace_slug: "any" }
    # The before-action redirects unauthenticated requests to /sign_in.
    assert_response :redirect
    assert_match %r{/sign_in}, response.location
  end

  test "send_to_workspace accepts non-admin workspace members" do
    owner = User.create!(email_address: "snd-o-#{SecureRandom.hex(4)}@example.com", role: "user")
    ws    = Workspace.create!(name: "Member WS", owner: owner)
    ws.social_accounts.create!(platform: "x", connected_by: owner, handle: "@m",
      external_id: SecureRandom.hex(4), access_token: "AT", refresh_token: "RT",
      token_expires_at: 2.hours.from_now, status: "active")

    member = User.create!(email_address: "snd-mem-#{SecureRandom.hex(4)}@example.com", role: "user")
    ws.memberships.create!(user: member, role: "editor")

    sign_in_as(member)
    assert_difference -> { WorkspaceDraft.count }, 1 do
      post "/nykitchen/send_to_workspace",
           params: { text: "Hi from a member", event_url: "https://nykitchen.com/event/y", workspace_slug: ws.slug }
    end
    assert JSON.parse(response.body)["ok"]
  end

  test "send_to_workspace 404s when slug doesn't match a workspace the admin belongs to" do
    admin = User.create!(email_address: "snd-n-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(admin)
    post "/nykitchen/send_to_workspace", params: { text: "hi", workspace_slug: "nonexistent" }
    assert_response :not_found
    assert_equal "workspace_not_found", JSON.parse(response.body)["error"]
  end

  test "send_to_workspace 404s when slug belongs to a workspace the admin is not a member of" do
    admin   = User.create!(email_address: "snd-o-#{SecureRandom.hex(4)}@example.com", role: "admin")
    outside = User.create!(email_address: "snd-x-#{SecureRandom.hex(4)}@example.com", role: "admin")
    ws = Workspace.create!(name: "Not Mine", owner: outside)
    sign_in_as(admin)
    post "/nykitchen/send_to_workspace", params: { text: "hi", workspace_slug: ws.slug }
    assert_response :not_found
  end

  test "send_to_workspace errors when picked workspace has no connected accounts" do
    admin = User.create!(email_address: "snd-p-#{SecureRandom.hex(4)}@example.com", role: "admin")
    ws = Workspace.create!(name: "Empty WS", owner: admin)
    sign_in_as(admin)
    post "/nykitchen/send_to_workspace", params: { text: "hi", workspace_slug: ws.slug }
    assert_response :unprocessable_entity
    assert_equal "no_platforms", JSON.parse(response.body)["error"]
  end

  test "event card uses kitchen-slugged workspace as the default Send to Social Agent destination" do
    user = User.create!(email_address: "snd-i-#{SecureRandom.hex(4)}@example.com", role: "user")
    a = Workspace.create!(name: "Aardvark Brand", owner: user)
    a.social_accounts.create!(platform: "x", connected_by: user, handle: "@a", external_id: "1",
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now, status: "active")
    k = Workspace.create!(name: "NY Kitchen Co", owner: user)
    k.social_accounts.create!(platform: "x", connected_by: user, handle: "@k", external_id: "2",
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now, status: "active")
    create_event("Pasta 101", 2.days.from_now, "InStock")

    sign_in_as(user)
    get nyk_list_path
    assert_response :success

    # The event card bakes the default workspace slug into a data attribute
    # that the social-post Stimulus controller reads when firing the handoff.
    # Kitchen-slugged workspace sorts first.
    assert_match %r{data-social-post-workspace-slug-value="#{k.slug}"}, response.body
  end

  # --- Agents hub coverage --------------------------------------------------

  test "anonymous visitor sees the hub (shareable)" do
    sign_out
    get nykitchen_path
    assert_response :success
    assert_match /List Agent/, response.body
  end

  test "anonymous click on List bounces to sign-in" do
    sign_out
    get nyk_list_path
    assert_redirected_to %r{/sign_in}
  end

  test "anonymous click on Test bounces to sign-in" do
    sign_out
    get nyk_test_path
    assert_redirected_to %r{/sign_in}
  end

  test "anonymous click on Data bounces to sign-in" do
    sign_out
    get nyk_data_path
    assert_redirected_to %r{/sign_in}
  end

  test "hub renders four agent cards" do
    create_event("Pasta 101", 2.days.from_now, "InStock")
    get nykitchen_path
    assert_response :success
    assert_match /List Agent/,   response.body
    assert_match /Test Agent/,   response.body
    assert_match /Data Agent/,   response.body
    assert_match /Social Agent/, response.body
  end

  test "hub redirects legacy ?tab=smoke to /nykitchen/test" do
    get nykitchen_path(tab: "smoke")
    assert_redirected_to nyk_test_path
    assert_equal 301, response.status
  end

  test "hub redirects legacy ?tab=smoke&status=failed preserving the status param" do
    get nykitchen_path(tab: "smoke", status: "failed")
    assert_redirected_to nyk_test_path(status: "failed")
  end

  test "hub redirects legacy ?tab=scrapes to /nykitchen/data" do
    get nykitchen_path(tab: "scrapes")
    assert_redirected_to nyk_data_path
    assert_equal 301, response.status
  end

  test "hub redirects legacy ?tab=list to /nykitchen/list" do
    get nykitchen_path(tab: "list")
    assert_redirected_to nyk_list_path
  end

  test "nyk_test_path renders smoke content with breadcrumbs" do
    get nyk_test_path
    assert_response :success
    assert_match /Test Agent/,    response.body
    assert_match /← NY Kitchen/,  response.body
    assert_match /Smoke Tests/,   response.body
  end

  test "nyk_data_path renders scrapes content with breadcrumbs" do
    get nyk_data_path
    assert_response :success
    assert_match /Data Agent/,   response.body
    assert_match /← NY Kitchen/, response.body
    assert_match /Scrapes/,      response.body
  end

  test "nyk_social_path renders the NYK workspace composer in-place" do
    admin = User.create!(email_address: "nyk-social-#{SecureRandom.hex(4)}@example.com", role: "admin")
    Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = admin }
    Workspace.find_by(slug: "nykitchen").tap { |w| w.memberships.find_or_create_by!(user: admin, role: "owner") }
    sign_in_as(admin)
    get nyk_social_path
    assert_response :success
    # The composer view renders, not a redirect — URL stays /nykitchen/social.
    assert_match %r{name="workspace\[timezone\]"}, response.body
  end

  test "nyk_list_path renders breadcrumbs above the list" do
    create_event("Pasta 101", 2.days.from_now, "InStock")
    get nyk_list_path
    assert_response :success
    assert_match /← NY Kitchen/, response.body
  end

  # ----- Display Agent (/nykitchen/display + /nykitchen/display/settings) -----

  test "display: public, no auth, filters out sold-out events" do
    create_event("Available Pasta",  3.days.from_now, "InStock")
    create_event("Limited Wine",     4.days.from_now, "Limited")
    create_event("Sold Out Cheese",  5.days.from_now, "SoldOut")
    create_event("Closed Baking",    6.days.from_now, "Closed")

    delete session_path # sign out — display is public
    get nyk_display_path
    assert_response :success
    assert_match "Available Pasta",  response.body
    assert_match "Limited Wine",     response.body
    refute_match "Sold Out Cheese",  response.body, "Sold-out events must not render on the display"
    refute_match "Closed Baking",    response.body, "Closed events must not render on the display"
  end

  test "display: caps at slide_count setting" do
    7.times { |i| create_event("Class #{i}", (i + 1).days.from_now, "InStock") }
    nyk_display_agent.update_settings(slide_count: 3)

    delete session_path
    get nyk_display_path
    assert_response :success
    # 3 slides actually rendered; "Class 6" exists but should be omitted.
    assert_match "Class 0", response.body
    assert_match "Class 2", response.body
    refute_match "Class 6", response.body
    # Header should show "Next 3 of 7"
    assert_match(/Next 3 of 7/, response.body)
  end

  test "display: private mode returns 404 without a token" do
    create_event("Hidden Class", 3.days.from_now, "InStock")
    nyk_display_agent.update_settings(visibility: "private")
    nyk_display_agent.rotate_share_token!

    delete session_path
    get nyk_display_path
    assert_response :not_found
  end

  test "display: private mode 404s with a wrong token" do
    create_event("Hidden Class", 3.days.from_now, "InStock")
    nyk_display_agent.update_settings(visibility: "private")
    nyk_display_agent.rotate_share_token!

    delete session_path
    get nyk_display_path(token: "nope")
    assert_response :not_found
  end

  test "display: private mode succeeds with the right token" do
    create_event("Hidden Class", 3.days.from_now, "InStock")
    nyk_display_agent.update_settings(visibility: "private")
    token = nyk_display_agent.rotate_share_token!

    delete session_path
    get nyk_display_path(token: token)
    assert_response :success
    assert_match "Hidden Class", response.body
  end

  test "display: show_price=false hides price even when event has one" do
    @snapshot.kitchen_events.create!(
      url: "https://nykitchen.com/events/pricey",
      name: "Pricey Class", start_at: 3.days.from_now,
      availability: "InStock", price: "190.00"
    )
    nyk_display_agent.update_settings(show_price: false)

    delete session_path
    get nyk_display_path
    assert_response :success
    refute_match "$190.00", response.body
    refute_match "190.00",  response.body
  end

  test "display_settings: requires authentication" do
    delete session_path
    get nyk_display_settings_path
    assert_response :redirect # /sign_in
  end

  test "update_display_settings: owner can save" do
    nyk_workspace.memberships.find_or_create_by!(user: @default_user) { |m| m.role = "owner" }

    patch nyk_display_settings_path, params: {
      settings: { slide_count: 9, advance_seconds: 15, refresh_minutes: 30,
                  show_price: "1", show_spots: "0", show_end_time: "1", show_image: "1",
                  visibility: "public" }
    }
    assert_redirected_to nyk_display_settings_path

    agent = nyk_display_agent
    assert_equal 9,     agent.setting(:slide_count)
    assert_equal false, agent.setting(:show_spots)
    assert_equal true,  agent.setting(:show_image)
  end

  test "update_display_settings: non-admin gets alerted, settings unchanged" do
    # nyk_workspace is owned by @default_user (auto-membership as owner).
    # Sign in a different user with only a "member" workspace role.
    member = User.create!(email_address: "kc-mem-#{SecureRandom.hex(4)}@example.com")
    nyk_workspace.memberships.create!(user: member, role: "viewer")
    sign_in_as(member)
    original = nyk_display_agent.setting(:slide_count)

    patch nyk_display_settings_path, params: { settings: { slide_count: 99 } }
    assert_redirected_to nyk_display_settings_path
    assert_equal "Only workspace admins can change Display settings.", flash[:alert]

    assert_equal original, nyk_display_agent.reload.setting(:slide_count)
  end

  test "update_display_settings: flipping to private generates a share token" do
    nyk_workspace.memberships.find_or_create_by!(user: @default_user) { |m| m.role = "owner" }

    patch nyk_display_settings_path, params: { settings: { visibility: "private" } }
    assert_redirected_to nyk_display_settings_path

    assert_equal "private", nyk_display_agent.setting(:visibility)
    assert nyk_display_agent.setting(:share_token).present?, "Token should auto-generate"
  end

  test "rotate_display_token: owner gets a new token, old one stops working" do
    nyk_workspace.memberships.find_or_create_by!(user: @default_user) { |m| m.role = "owner" }
    nyk_display_agent.update_settings(visibility: "private")
    old_token = nyk_display_agent.share_token_or_generate!

    post nyk_display_rotate_token_path
    assert_redirected_to nyk_display_settings_path

    new_token = nyk_display_agent.reload.setting(:share_token)
    refute_equal old_token, new_token

    # Old token should now 404.
    create_event("Hidden", 3.days.from_now, "InStock")
    delete session_path
    get nyk_display_path(token: old_token)
    assert_response :not_found
  end

  test "display_heartbeat records last_seen when the token matches the private screen URL" do
    nyk_display_agent.update_settings(visibility: "private")
    token = nyk_display_agent.share_token_or_generate!

    assert_nil Setting.time("nyk_display:last_seen_at")
    post nyk_display_heartbeat_path, params: { token: token }
    assert_response :no_content

    seen = Setting.time("nyk_display:last_seen_at")
    assert_not_nil seen, "a matching heartbeat should record last-seen"
    assert_in_delta Time.current, seen, 5.seconds
  end

  test "display_heartbeat ignores a wrong or blank token" do
    nyk_display_agent.update_settings(visibility: "private")
    nyk_display_agent.share_token_or_generate!

    post nyk_display_heartbeat_path, params: { token: "not-the-token" }
    assert_response :no_content
    assert_nil Setting.time("nyk_display:last_seen_at"), "wrong token must not count as the screen"

    post nyk_display_heartbeat_path
    assert_response :no_content
    assert_nil Setting.time("nyk_display:last_seen_at"), "blank token must not count"
  end

  test "hub shows the Display Agent live after a recent heartbeat in private mode" do
    nyk_display_agent.update_settings(visibility: "private")
    Setting.touch_time("nyk_display:last_seen_at")

    get nykitchen_path
    assert_response :success
    assert_match "Carousel live at NY Kitchen", response.body
  end

  test "hub shows the Display Agent red when private but no recent heartbeat" do
    nyk_display_agent.update_settings(visibility: "private")
    Setting.set("nyk_display:last_seen_at", 1.hour.ago.iso8601)

    get nykitchen_path
    assert_response :success
    assert_match "Not running at NY Kitchen", response.body
    assert_match "bg-red-500", response.body
  end

  private

  def create_event(name, start_at, availability)
    @snapshot.kitchen_events.create!(
      url: "https://nykitchen.com/events/#{name.parameterize}",
      name: name,
      start_at: start_at,
      availability: availability
    )
  end

  def nyk_workspace
    @nyk_workspace ||= Workspace.find_or_create_by!(slug: "nykitchen") do |w|
      w.name = "NY Kitchen"
      w.owner = @default_user
    end
  end

  def nyk_display_agent
    nyk_workspace.agent_for("display")
  end
end
