require_relative "system_test_helper"

# End-to-end happy path for a new email signup:
#   1. Sign up
#   2. Land on /workspaces (post-pivot landing page; the old fleet-dashboard
#      route at / is gone)
#   3. Sign out
#   4. Sign back in (lands on /workspaces again)
#   5. Delete the account (Apple-required flow — exercises the FK cascades)
class SignupE2ETest < SystemTestCase
  test "new user signup → workspaces → logout → login → delete" do
    email    = "e2e-signup-#{SecureRandom.hex(4)}@example.com"
    password = "SignupTest2026!"

    @page.set_viewport_size(width: 1280, height: 800)

    # Step 1: sign up
    @page.goto("#{BASE_URL}/registration/new")
    @page.fill('input[name="user[email_address]"]', email)
    @page.fill('input[name="user[password]"]', password)
    @page.fill('input[name="user[password_confirmation]"]', password)
    @page.click('button[type="submit"]')
    @page.wait_for_url("#{BASE_URL}/workspaces")

    body = @page.content
    # Brand-new user has no workspace memberships yet — they get the
    # invite-only empty state on /workspaces.
    assert_match(/Workspaces are by invitation/i, body, "Empty state on /workspaces for brand-new user")

    # Hamburger dropdown for non-admins should expose Workspaces / Settings / Sign Out.
    nav_html = @page.locator("nav").inner_html
    assert_match(/Workspaces/, nav_html, "Nav has Workspaces")
    assert_match(/Settings/,   nav_html, "Nav has Settings")
    assert_match(/Sign Out/,   nav_html, "Nav has Sign Out")

    # Step 2: open the hamburger menu, then sign out (Sign Out lives inside
    # the dropdown for non-admins).
    @page.click('button[aria-label="Menu"]')
    sleep 0.2
    @page.click('form[action="/session"][method="post"] button[type="submit"]', force: true)
    50.times { break if @page.url == "#{BASE_URL}/"; sleep 0.1 }
    after_logout = @page.content
    assert_match(/Sign In/, after_logout, "Sign In link appears after logout")

    # Step 3: sign back in
    @page.goto("#{BASE_URL}/session/new")
    @page.fill('input[name="email_address"]', email)
    @page.fill('input[name="password"]', password)
    @page.click('button[type="submit"]')
    @page.wait_for_url("#{BASE_URL}/workspaces")
    assert_match(/Workspaces are by invitation/i, @page.content, "Back on /workspaces after re-sign-in")

    # Step 4: delete account (FK cascades must succeed — no 500)
    @page.goto("#{BASE_URL}/settings")
    @page.click('button[data-action="click->account-deletion#open"]')
    @page.fill('input[name="password"]', password)
    @page.click('input[type="submit"][value="Delete my account"]')
    50.times { break if @page.url == "#{BASE_URL}/"; sleep 0.1 }
    final = @page.content
    refute_match(/Internal Server Error/i, final, "No 500 on account delete")
    assert_match(/Sign In|Sign Up/, final, "Public home shown after delete")
    refute User.exists?(email_address: email), "User row removed from DB"
  end
end
