require "test_helper"
require "playwright"

# Smoke test: verifies the Face ID button appears on sign-in and homepage
# in a mobile viewport (simulating Capacitor iOS app).
#
# Run with:  RUN_SMOKE=true bin/rails test test/smoke/faceid_button_test.rb
# Watch it:  HEADFUL=true RUN_SMOKE=true bin/rails test test/smoke/faceid_button_test.rb
class FaceIdButtonTest < ActiveSupport::TestCase
  BASE_URL = ENV["SMOKE_BASE_URL"] || "http://localhost:3000"

  def self.runnable_methods
    ENV["RUN_SMOKE"] == "true" ? super : []
  end

  test "Face ID button markup exists on sign-in page (hidden without Capacitor)" do
    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
      iphone = pw.devices["iPhone 14"]

      browser = pw.chromium.launch(headless: !headful)
      context = browser.new_context(**iphone)
      page = context.new_page

      begin
        page.goto("#{BASE_URL}/session/new", timeout: 15_000, waitUntil: "domcontentloaded")

        # Button should exist in DOM
        btn = page.locator("#faceid-signin-btn")
        assert btn.count > 0, "Face ID button should exist in DOM on sign-in page"

        # Button should be hidden (display:none) since we're not in Capacitor
        visible = btn.evaluate("el => window.getComputedStyle(el).display !== 'none'")
        refute visible, "Face ID button should be hidden outside Capacitor"

        # JS partial should be loaded
        page_source = page.content
        assert page_source.include?("BiometricAuth"), "Page should include BiometricAuth JS"
        assert page_source.include?("saveCredentials"), "Page should include saveCredentials JS"

        puts "  Face ID button exists on sign-in page (hidden without Capacitor)"
      ensure
        context.close
        browser.close
      end
    end
  end

  test "Face ID button markup exists on homepage for all users" do
    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
      iphone = pw.devices["iPhone 14"]

      browser = pw.chromium.launch(headless: !headful)
      context = browser.new_context(**iphone)
      page = context.new_page

      begin
        page.goto(BASE_URL, timeout: 15_000, waitUntil: "domcontentloaded")

        # Button should exist in DOM on homepage
        btn = page.locator("#faceid-signin-btn")
        assert btn.count > 0, "Face ID button should exist on homepage"

        puts "  Face ID button exists on homepage"
      ensure
        context.close
        browser.close
      end
    end
  end

  test "Face ID button exists on homepage after sign-in" do
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

        # Face ID button should still be on homepage after sign-in
        btn = page.locator("#faceid-signin-btn")
        assert btn.count > 0, "Face ID button should exist on homepage even after sign-in"

        puts "  Face ID button exists on homepage after sign-in"
      ensure
        context.close
        browser.close
      end
    end
  end

  private

  def playwright_cli
    ENV["PLAYWRIGHT_CLI_PATH"] || "npx playwright"
  end
end
