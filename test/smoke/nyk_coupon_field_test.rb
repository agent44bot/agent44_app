require "test_helper"
require "fileutils"
require "playwright"

# Smoke test for the coupon code field on NY Kitchen event checkout.
#
# Bug report: users want to apply coupon codes at checkout but the
# coupon field may not be visible or functional.
#
# Steps:
#   1. Load /calendar/ and find an available (purchasable) event
#   2. Navigate to its detail page
#   3. Fill in attendee info, set ticket quantity >= 1, click "GET TICKETS"
#   4. Follow redirect to the WooCommerce /checkout/ page
#   5. Click "Have a coupon? Click here to enter your coupon code"
#   6. Assert the coupon input field + APPLY button are visible
#
# Run with:  RUN_SMOKE=true bin/rails test test/smoke/nyk_coupon_field_test.rb
# Watch it:  HEADFUL=true RUN_SMOKE=true bin/rails test test/smoke/nyk_coupon_field_test.rb
class NykCouponFieldTest < ActiveSupport::TestCase
  TARGET_URL = "https://nykitchen.com/calendar/"
  ARTIFACT_DIR = Rails.root.join("tmp", "smoke")

  def self.runnable_methods
    ENV["RUN_SMOKE"] == "true" ? super : []
  end

  setup do
    FileUtils.mkdir_p(ARTIFACT_DIR)
    @stamp = Time.now.strftime("%Y%m%d-%H%M%S")
  end

  test "coupon code field is visible and functional on an available event" do
    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
      browser = pw.chromium.launch(headless: !headful)
      context = browser.new_context(viewport: { width: 1280, height: 900 })
      page = context.new_page

      begin
        # 1. Nav forward 3 months on the calendar, then collect event URLs
        #    from that furthest month first (most likely to have availability).
        page.goto(TARGET_URL, timeout: 30_000, waitUntil: "domcontentloaded")
        page.wait_for_selector(".tribe-events-calendar-month__calendar-event", timeout: 15_000)
        dismiss_newsletter_popup(page)

        months_urls = [] # array of arrays, one per month
        MONTHS_TO_SEARCH = 3
        (MONTHS_TO_SEARCH + 1).times do |month_idx|
          urls = page.evaluate(<<~JS) || []
            Array.from(
              document.querySelectorAll('.tribe-events-calendar-month__calendar-event-title-link')
            ).map(a => a.href).filter(Boolean)
          JS
          months_urls << urls.uniq
          puts "  📅 Month #{month_idx}: #{urls.uniq.size} event links"

          if month_idx < MONTHS_TO_SEARCH
            next_btn = page.locator('a.tribe-events-c-top-bar__nav-link--next')
            break if next_btn.count == 0
            next_btn.first.click
            page.wait_for_timeout(3_000)
          end
        end

        # Start from the furthest month (most likely to have available events)
        # and work backward to avoid wasting time on past/sold-out events
        event_urls = months_urls.reverse.flatten.uniq
        assert event_urls.any?, "No event links found across #{MONTHS_TO_SEARCH + 1} months of calendar"
        puts "  🔍 Searching #{event_urls.size} events (furthest month first)"

        # 2. Visit events until we find one that's available (has a ticket section
        #    with purchasable tickets, not sold out / closed)
        found_event = false
        event_urls.each_with_index do |url, idx|
          page.goto(url, timeout: 30_000, waitUntil: "domcontentloaded")
          page.wait_for_timeout(2_000)

          # Skip past events or sold-out events
          body_text = page.evaluate("document.body.innerText") || ""
          if body_text.match?(/this event has passed/i)
            puts "    [#{idx + 1}/#{event_urls.size}] past — skipping"
            next
          end
          if body_text.match?(/tickets are no longer available/i)
            puts "    [#{idx + 1}/#{event_urls.size}] closed — skipping"
            next
          end

          # Check for a ticket section with available tickets
          has_tickets = page.locator(".tribe-tickets, .tribe-tickets__tickets-wrapper").count > 0
          unless has_tickets
            puts "    [#{idx + 1}/#{event_urls.size}] no ticket section — skipping"
            next
          end

          # Check it's not sold out in the ticket area
          ticket_text = page.evaluate(<<~JS) || ""
            (document.querySelector('.tribe-tickets') || {}).innerText || ''
          JS
          if ticket_text.match?(/sold\s*out/i) && !ticket_text.match?(/\d+\s+available/i)
            puts "    [#{idx + 1}/#{event_urls.size}] sold out — skipping"
            next
          end

          found_event = true
          puts "  🎫 [#{idx + 1}/#{event_urls.size}] Found available event: #{url}"
          break
        end

        unless found_event
          skip "No available (purchasable) events found across #{event_urls.size} events in #{MONTHS_TO_SEARCH + 1} months"
        end

        # 3. Scroll the ticket section into view and ensure quantity >= 1
        page.evaluate(<<~JS)
          (document.querySelector('.tribe-tickets') || document.body)
            .scrollIntoView({behavior: 'smooth', block: 'center'});
        JS
        page.wait_for_timeout(1_000)

        # Make sure at least one ticket has quantity >= 1
        quantity_display = page.locator('.tribe-tickets__tickets-item-quantity-number-input, input[type="number"]').first
        if quantity_display && quantity_display.input_value.to_i < 1
          plus_btn = page.locator('.tribe-tickets__tickets-item-quantity-number-input-increase, button:has-text("+")').first
          plus_btn.click if plus_btn
          page.wait_for_timeout(500)
        end

        page.screenshot(path: ARTIFACT_DIR.join("nyk-coupon-1-tickets-#{@stamp}.png").to_s, fullPage: true)

        # 4. Click "GET TICKETS" to expand the attendee form
        get_tickets_btn = page.locator(
          'button:has-text("Get Tickets"), ' \
          'button:has-text("GET TICKETS"), ' \
          '.tribe-tickets__buy, ' \
          'button[type="submit"].tribe-common-c-btn'
        )

        assert get_tickets_btn.count > 0,
               "Could not find 'GET TICKETS' button. " \
               "Screenshot: #{ARTIFACT_DIR.join("nyk-coupon-1-tickets-#{@stamp}.png")}"

        puts "  🎟  Clicking 'GET TICKETS'..."
        get_tickets_btn.first.click
        page.wait_for_timeout(3_000)

        page.screenshot(path: ARTIFACT_DIR.join("nyk-coupon-2-attendee-#{@stamp}.png").to_s, fullPage: true)

        # 5. Fill in required attendee fields so checkout can proceed.
        #    The form requires attendee name + age confirmation per ticket.
        fill_attendee_fields(page)
        page.wait_for_timeout(1_000)
        page.screenshot(path: ARTIFACT_DIR.join("nyk-coupon-3-filled-#{@stamp}.png").to_s, fullPage: true)

        # 6. Click "CHECKOUT NOW" to add to cart and go to WooCommerce checkout.
        #    The attendee form has two buttons: "SAVE AND ADD CART" and "CHECKOUT NOW".
        checkout_btn = page.locator(
          'button:has-text("Checkout Now"), ' \
          'button:has-text("CHECKOUT NOW"), ' \
          'a:has-text("Checkout Now"), ' \
          'a:has-text("CHECKOUT NOW")'
        )

        # Fall back to "Save and Add Cart" if "Checkout Now" not found
        if checkout_btn.count == 0
          checkout_btn = page.locator(
            'button:has-text("Save and Add"), ' \
            'button:has-text("SAVE AND ADD"), ' \
            'button:has-text("Add to Cart"), ' \
            'button:has-text("ADD TO CART")'
          )
        end

        assert checkout_btn.count > 0,
               "Could not find 'CHECKOUT NOW' or 'SAVE AND ADD CART' button. " \
               "Screenshot: #{ARTIFACT_DIR.join("nyk-coupon-3-filled-#{@stamp}.png")}"

        puts "  🛒 Clicking '#{checkout_btn.first.inner_text.strip}'..."
        checkout_btn.first.click
        page.wait_for_timeout(5_000)

        page.screenshot(path: ARTIFACT_DIR.join("nyk-coupon-4-sidebar-#{@stamp}.png").to_s, fullPage: true)

        # 7. After adding to cart, a side cart sidebar slides in.
        #    Click the "Checkout" link inside it to reach /checkout/.
        unless page.url.include?("checkout")
          sidebar_checkout = page.locator(
            'a.elementor-button--checkout, ' \
            '.xoo-wsc-ft-btn-checkout, ' \
            '.widget_shopping_cart a[href*="checkout"]'
          )

          if sidebar_checkout.count > 0
            puts "  🛒 Found sidebar checkout, waiting for it to settle..."
            page.wait_for_timeout(2_000)
            puts "  🛒 Clicking sidebar 'Checkout' button..."
            sidebar_checkout.first.click
          else
            # No sidebar found — navigate directly to /checkout/
            puts "  🛒 No sidebar found, navigating directly to /checkout/..."
            page.goto("https://nykitchen.com/checkout/", timeout: 30_000, waitUntil: "domcontentloaded")
          end

          deadline = Time.now + 15
          while Time.now < deadline
            break if page.url.include?("checkout")
            page.wait_for_timeout(500)
          end
          page.wait_for_load_state("domcontentloaded", timeout: 15_000) rescue nil
          page.wait_for_timeout(3_000)
        end

        # Let the checkout page fully render before interacting
        page.wait_for_load_state("networkidle", timeout: 10_000) rescue nil
        page.wait_for_timeout(3_000)

        puts "  📄 Current URL: #{page.url}"
        page.screenshot(path: ARTIFACT_DIR.join("nyk-coupon-5-checkout-#{@stamp}.png").to_s, fullPage: true)

        assert page.url.include?("checkout"),
               "Did not reach checkout page. " \
               "Current URL: #{page.url}. " \
               "Screenshot: #{ARTIFACT_DIR.join("nyk-coupon-5-checkout-#{@stamp}.png")}"

        # 8. Dismiss the Elementor cart sidebar that overlaps the checkout page.
        #    It intercepts pointer events on the coupon link.
        page.evaluate(<<~JS)
          (function() {
            const style = document.createElement('style');
            style.textContent = `
              .elementor-menu-cart__main,
              .elementor-menu-cart__container,
              .widget_shopping_cart_content {
                display: none !important;
                pointer-events: none !important;
              }
            `;
            document.head.appendChild(style);
          })();
        JS
        page.wait_for_timeout(500)

        # 9. Look for "Have a coupon? Click here to enter your coupon code" link
        coupon_toggle = page.locator(
          'a:has-text("Click here to enter your coupon code"), ' \
          'a:has-text("coupon code"), ' \
          '.showcoupon, ' \
          '.woocommerce-info a[href*="showcoupon"], ' \
          'a.showcoupon'
        )

        assert coupon_toggle.count > 0,
               "No 'Have a coupon?' link found on the checkout page. " \
               "Screenshot: #{ARTIFACT_DIR.join("nyk-coupon-5-dismissed-#{@stamp}.png")}"

        puts "  🏷  Found 'Have a coupon?' link — clicking..."
        coupon_toggle.first.click
        page.wait_for_timeout(1_500)

        # 9. Assert the coupon input field + APPLY button appeared
        coupon_input = page.locator(
          'input[name="coupon_code"], ' \
          'input[placeholder*="Coupon code" i], ' \
          'input[placeholder*="coupon" i], ' \
          '#coupon_code'
        )

        page.screenshot(path: ARTIFACT_DIR.join("nyk-coupon-6-field-#{@stamp}.png").to_s, fullPage: true)

        assert coupon_input.count > 0,
               "Coupon input field did not appear after clicking the toggle. " \
               "Screenshots saved to #{ARTIFACT_DIR}"

        visible = coupon_input.first.visible?
        assert visible,
               "Coupon input field exists but is not visible. " \
               "Screenshots saved to #{ARTIFACT_DIR}"

        apply_btn = page.locator(
          'button:has-text("Apply"), ' \
          'button:has-text("APPLY"), ' \
          'button[name="apply_coupon"], ' \
          '.coupon button[type="submit"]'
        )
        assert apply_btn.count > 0,
               "Coupon APPLY button not found next to the coupon input. " \
               "Screenshots saved to #{ARTIFACT_DIR}"

        puts "  ✅ Coupon code field and APPLY button are visible on checkout page"
      ensure
        browser&.close rescue nil
      end
    end
  end

  private

  def playwright_cli
    path = Rails.root.join("node_modules", ".bin", "playwright")
    unless File.executable?(path)
      skip "Playwright CLI not found. Run: npm install playwright && npx playwright install chromium"
    end
    path.to_s
  end

  # Fill in the minimum required attendee fields so the ticket form
  # can proceed to checkout. Uses dummy data — we never actually submit payment.
  def fill_attendee_fields(page)
    # Attendee name fields (required) — fill all visible name inputs
    name_fields = page.locator(
      'input[name*="attendee"][name*="name" i]:visible, ' \
      'input[placeholder*="Name" i]:visible'
    )
    name_fields.count.times do |i|
      field = name_fields.nth(i)
      field.fill("Smoke Test") if field.input_value.to_s.empty?
    end
    puts "    filled #{name_fields.count} name field(s)"

    # Age confirmation dropdowns (required) — select "Yes, the guest is 21."
    age_selects = page.locator(
      'select[name*="attendee"]:visible, ' \
      'select[name*="21" i]:visible'
    )
    age_selects.count.times do |i|
      sel = age_selects.nth(i)
      begin
        sel.select_option(label: /yes.*21/i)
      rescue
        sel.select_option(index: 1) rescue nil
      end
    end
    puts "    filled #{age_selects.count} age dropdown(s)"

    # Checkbox for policies (required) — the checkbox is inside the
    # attendee form. Try multiple strategies to find it.
    policy_checked = false

    # Strategy 1: click the checkbox input directly
    checkboxes = page.locator('input[type="checkbox"]:visible')
    checkboxes.count.times do |i|
      cb = checkboxes.nth(i)
      cb.check unless cb.checked?
      policy_checked = true
    end

    # Strategy 2: click the label text if checkboxes weren't found
    unless policy_checked
      label = page.locator(
        'label:has-text("policies"), ' \
        'label:has-text("acknowledge"), ' \
        'span:has-text("I have read")'
      )
      if label.count > 0
        label.first.click
        policy_checked = true
      end
    end

    puts "    checked #{policy_checked ? 'policy checkbox' : 'NO checkbox found'}"
    puts "  📝 Filled attendee fields"
  end

  def dismiss_newsletter_popup(page)
    page.evaluate(<<~JS)
      (function() {
        const style = document.createElement('style');
        style.textContent = `
          [id^="elementor-popup-modal-"] {
            display: none !important;
            pointer-events: none !important;
          }
        `;
        document.head.appendChild(style);
      })();
    JS
    page.wait_for_timeout(400)
  end
end
