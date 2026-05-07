require_relative "system_test_helper"

# End-to-end happy path for a new email signup:
#   1. Sign up
#   2. Land on the member dashboard, hamburger has the right entries
#   3. Sign out
#   4. Sign back in
#   5. Delete the account (Apple-required flow — exercises the FK cascades)
class SignupE2ETest < SystemTestCase
  test "new user signup → dashboard → logout → login → delete" do
    email    = "e2e-signup-#{SecureRandom.hex(4)}@example.com"
    password = "SignupTest2026!"

    # Use a desktop viewport — the desktop nav exposes Sign Out as a visible
    # button. We separately spot-check the mobile hamburger contents via DOM
    # inspection (no clicks) so we don't fight with toggle-class visibility.
    @page.set_viewport_size(width: 1280, height: 800)

    # Step 1: sign up
    @page.goto("#{BASE_URL}/registration/new")
    @page.fill('input[name="user[email_address]"]', email)
    @page.fill('input[name="user[password]"]', password)
    @page.fill('input[name="user[password_confirmation]"]', password)
    @page.click('button[type="submit"]')
    @page.wait_for_url("#{BASE_URL}/")

    body = @page.content
    assert_match(/What can a fleet do for you/, body, "Member dashboard rendered after sign-up")

    # Step 2: dashboard tiles + hamburger contents
    %w[Smoke\ testing Calendar AI-enhanced Custom\ agent].each do |label|
      assert_match(/#{Regexp.escape(label)}/, body, "Dashboard tile: #{label}")
    end

    # The mobile menu's links are in the DOM even when the menu is hidden.
    mobile_menu_html = @page.locator('[data-nav-target="menu"]').inner_html
    assert_match(/My Fleet/,  mobile_menu_html, "Hamburger has My Fleet")
    assert_match(/Settings/,  mobile_menu_html, "Hamburger has Settings")
    assert_match(/Sign Out/,  mobile_menu_html, "Hamburger has Sign Out")
    refute_match(/\bCrypto\b/, mobile_menu_html, "Hamburger does NOT have admin Crypto entry")

    # Step 3: sign out (desktop nav)
    @page.click('form[action="/session"][method="post"] button[type="submit"]')
    @page.wait_for_url("#{BASE_URL}/")
    @page.wait_for_load_state(state: "networkidle")
    after_logout = @page.content
    refute_match(/What can a fleet do for you/, after_logout, "Dashboard gone after logout")
    assert_match(/Sign In/, after_logout, "Sign In link appears after logout")

    # Step 4: sign back in
    @page.goto("#{BASE_URL}/session/new")
    @page.fill('input[name="email_address"]', email)
    @page.fill('input[name="password"]', password)
    @page.click('button[type="submit"]')
    @page.wait_for_url("#{BASE_URL}/")
    assert_match(/What can a fleet do for you/, @page.content, "Back on dashboard after re-sign-in")

    # Step 5: delete account (FK cascades must succeed — no 500)
    @page.goto("#{BASE_URL}/settings")
    @page.click('button[data-action="click->account-deletion#open"]')
    @page.fill('input[name="password"]', password)
    @page.click('input[type="submit"][value="Delete my account"]')
    @page.wait_for_url("#{BASE_URL}/", timeout: 10_000)
    final = @page.content
    refute_match(/Internal Server Error/i, final, "No 500 on account delete")
    refute_match(/What can a fleet do for you/, final, "Dashboard gone after delete")
    assert_match(/Sign In|Sign Up/, final, "Public home shown after delete")
    refute User.exists?(email_address: email), "User row removed from DB"
  end
end
