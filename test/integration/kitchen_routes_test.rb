require "test_helper"

# Multi-tenant slice 2: the kitchen routes mount once at /:workspace_slug/*.
# /nykitchen/* is unchanged; any kitchen-enabled workspace gets the same pages
# under its own slug; non-members are shut out; top-level routes are safe.
class KitchenRoutesTest < ActionDispatch::IntegrationTest
  setup do
    @nyk = nyk_workspace!
    @owner = User.create!(email_address: "flx-owner-#{SecureRandom.hex(3)}@example.com")
    @flx = Workspace.create!(name: "FLX Culinary", slug: "flxculinary", owner: @owner, kitchen_enabled: true)
    KitchenWorkspaceConstraint.reset!
    @flx.kitchen_snapshots.create!(taken_on: Date.current).kitchen_events.create!(
      url: "https://flx.example/e/1", name: "Tenant Two Class", start_at: 3.days.from_now, availability: "InStock")
    @nyk.kitchen_snapshots.create!(taken_on: Date.current).kitchen_events.create!(
      url: "https://nykitchen.com/e/1", name: "Pasta Night", start_at: 3.days.from_now, availability: "InStock")
  end

  test "a second kitchen workspace serves the same pages under its slug, with its own data" do
    sign_in_as(@owner)
    get "/flxculinary/list"
    assert_response :success
    assert_match "Tenant Two Class", response.body
    assert_no_match "Pasta Night", response.body
    get "/flxculinary/display/print"
    assert_response :success
    get "/flxculinary"
    assert_response :success
  end

  test "links rendered inside a tenant's page point at that tenant" do
    sign_in_as(@owner)
    get "/flxculinary/list"
    assert_match %r{href="/flxculinary/}, response.body
    assert_no_match %r{href="/nykitchen/}, response.body
  end

  test "links rendered outside any kitchen page default to NY Kitchen" do
    admin = User.create!(email_address: "adm-#{SecureRandom.hex(3)}@example.com", role: "admin")
    sign_in_as(admin)
    get "/workspaces"
    assert_response :success
    assert_match %r{href="/nykitchen"}, response.body
  end

  test "a non-member signed-in user gets 404 on another workspace's kitchen pages" do
    stranger = User.create!(email_address: "str-#{SecureRandom.hex(3)}@example.com")
    sign_in_as(stranger)
    get "/flxculinary/list"
    assert_response :not_found
    get "/nykitchen/list"
    assert_response :not_found
    # Public pages stay public.
    get "/nykitchen"
    assert_response :success
    get "/nykitchen/display/print"
    assert_response :success
  end

  test "site admins and the App Store reviewer reach every kitchen workspace" do
    admin = User.create!(email_address: "adm2-#{SecureRandom.hex(3)}@example.com", role: "admin")
    sign_in_as(admin)
    get "/flxculinary/list"
    assert_response :success
    reviewer = User.create!(email_address: "rev-#{SecureRandom.hex(3)}@example.com", role: "reviewer")
    sign_in_as(reviewer)
    get "/nykitchen/list"
    assert_response :success
  end

  test "a workspace that is not kitchen-enabled has no kitchen pages" do
    Workspace.create!(name: "Plain", slug: "plainws", owner: @owner)
    sign_in_as(@owner)
    get "/plainws/list"
    assert_response :not_found
    get "/plainws"
    assert_response :not_found
  end

  test "enabling the kitchen flag makes the pages appear without a restart" do
    late = Workspace.create!(name: "Late", slug: "latews", owner: @owner)
    sign_in_as(@owner)
    get "/latews"
    assert_response :not_found
    late.update!(kitchen_enabled: true)
    get "/latews"
    assert_response :success
  end

  test "top-level routes are never shadowed and slugs that would collide are refused" do
    admin = User.create!(email_address: "adm3-#{SecureRandom.hex(3)}@example.com", role: "admin")
    sign_in_as(admin)
    get "/workspaces"
    assert_response :success
    get "/jobs"
    assert_response :success
    ws = Workspace.new(name: "Jobs", slug: "jobs", owner: @owner)
    assert_not ws.valid?
    assert_includes ws.errors[:slug], "is reserved"
    assert Workspace.reserved_slugs.include?("admin")
    assert Workspace.reserved_slugs.include?("workspaces")
  end

  test "a second tenant's /billing goes to the generic per-workspace billing page, never NYK's numbers" do
    sign_in_as(@owner)
    get "/flxculinary/billing"
    assert_redirected_to "/workspaces/flxculinary/billing"
    admin = User.create!(email_address: "adm4-#{SecureRandom.hex(3)}@example.com", role: "admin")
    sign_in_as(admin)
    get "/nykitchen/billing"
    assert_response :success
  end

  test "the /social alias renders the tenant's own composer" do
    sign_in_as(@owner)
    get "/flxculinary/social"
    assert_response :success
    assert_match "FLX Culinary", response.body
  end

  test "legacy handout redirects keep the tenant" do
    sign_in_as(@owner)
    get "/flxculinary/handouts/new"
    assert_redirected_to "/flxculinary/packets/new"
  end

  test "the AASA lists every kitchen slug with the QR-redirect exclusion first" do
    get "/.well-known/apple-app-site-association"
    assert_response :success
    paths = JSON.parse(response.body).dig("applinks", "details", 0, "paths")
    assert_includes paths, "/nykitchen/*"
    assert_includes paths, "/flxculinary/*"
    assert paths.index("NOT /flxculinary/r/*") < paths.index("/flxculinary/*")
  end
end
