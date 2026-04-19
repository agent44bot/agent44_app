require "test_helper"
require "fileutils"
require "playwright"

# Smoke test for the mobile hamburger menu on localhost.
#
# Uses Playwright WebKit with iPhone device emulation to verify that
# tapping the hamburger icon toggles the mobile navigation menu open
# and closed.
#
# Run with:  RUN_SMOKE=true bin/rails test test/smoke/hamburger_menu_test.rb
# Watch it:  HEADFUL=true RUN_SMOKE=true bin/rails test test/smoke/hamburger_menu_test.rb
class HamburgerMenuTest < ActiveSupport::TestCase
  ARTIFACT_DIR = Rails.root.join("tmp", "smoke")
  BASE_URL = ENV["SMOKE_BASE_URL"] || "http://localhost:3000"

  def self.runnable_methods
    ENV["RUN_SMOKE"] == "true" ? super : []
  end

  setup do
    FileUtils.mkdir_p(ARTIFACT_DIR)
    @stamp = Time.now.strftime("%Y%m%d-%H%M%S")
  end

  test "hamburger menu toggles mobile nav open and closed" do
    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
      iphone = pw.devices["iPhone 14"]

      browser = pw.chromium.launch(headless: !headful)
      context = browser.new_context(**iphone)
      page = context.new_page

      begin
        page.goto(BASE_URL, timeout: 15_000, waitUntil: "domcontentloaded")

        # Wait for nav to be present
        page.wait_for_selector('nav[data-controller*="nav"]', timeout: 5_000)

        # Mobile menu should be hidden initially
        menu = page.locator('[data-nav-target="menu"]')
        assert menu_hidden?(menu), "Mobile menu should be hidden on load"

        # Click the hamburger button
        hamburger = page.locator('[data-nav-target="menuBtn"]')
        hamburger.click
        page.wait_for_timeout(300)

        # Menu should now be visible
        screenshot(page, "after-open")
        refute menu_hidden?(menu), "Mobile menu should be visible after clicking hamburger"

        # Verify menu contains expected links
        menu_text = menu.text_content
        %w[Home Jobs].each do |label|
          assert menu_text.include?(label), "Mobile menu should contain '#{label}' link"
        end

        # Click hamburger again to close
        hamburger.click
        page.wait_for_timeout(300)

        # Menu should be hidden again
        screenshot(page, "after-close")
        assert menu_hidden?(menu), "Mobile menu should be hidden after second click"

        puts "✓ Hamburger menu toggle works correctly on mobile viewport"
      rescue => e
        screenshot(page, "failure")
        raise
      ensure
        context.close
        browser.close
      end
    end
  end

  test "admin sign-in and navigate to NY Kitchen via hamburger menu" do
    email = ENV["SMOKE_ADMIN_EMAIL"]
    password = ENV["SMOKE_ADMIN_PASSWORD"]
    skip "Set SMOKE_ADMIN_EMAIL and SMOKE_ADMIN_PASSWORD to run" unless email && password

    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
      iphone = pw.devices["iPhone 14"]

      browser = pw.chromium.launch(headless: !headful)
      context = browser.new_context(**iphone)
      page = context.new_page

      begin
        # Sign in
        page.goto("#{BASE_URL}/session/new", timeout: 15_000, waitUntil: "domcontentloaded")
        page.fill('input[name="email_address"]', email)
        page.fill('input[name="password"]', password)
        page.click('button[type="submit"]')
        page.wait_for_url("**/", timeout: 10_000)
        screenshot(page, "nyk-signed-in")

        # Open hamburger menu
        hamburger = page.locator('[data-nav-target="menuBtn"]')
        hamburger.click
        page.wait_for_timeout(300)

        # Verify NY Kitchen link is present (admin-only)
        nyk_link = page.locator('[data-nav-target="menu"] a', hasText: "NY Kitchen")
        assert nyk_link.visible?, "NY Kitchen link should be visible in mobile menu for admin"
        screenshot(page, "nyk-menu-open")

        # Click NY Kitchen
        nyk_link.click
        page.wait_for_url("**/nykitchen", timeout: 10_000)

        # Verify NY Kitchen page rendered
        heading = page.locator("h1", hasText: "NY Kitchen")
        assert heading.visible?, "NY Kitchen page heading should be visible"

        page_text = page.text_content("body")
        assert page_text.include?("Cooking classes"), "Page should show cooking classes description"
        screenshot(page, "nyk-page")

        puts "✓ Admin sign-in → hamburger → NY Kitchen page works correctly"
      rescue => e
        screenshot(page, "nyk-failure")
        raise
      ensure
        context.close
        browser.close
      end
    end
  end

  private

  def menu_hidden?(menu)
    menu.evaluate("el => el.classList.contains('hidden')")
  end

  def screenshot(page, label)
    path = ARTIFACT_DIR.join("hamburger-#{label}-#{@stamp}.png")
    page.screenshot(path: path.to_s)
  end

  def playwright_cli
    ENV["PLAYWRIGHT_CLI_PATH"] || "npx playwright"
  end
end
