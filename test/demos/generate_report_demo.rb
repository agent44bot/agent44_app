# Records the "Generate report" walkthrough video that's embedded in the
# generate page's "How it works" panel. Not a test (no asserts); a one-shot
# recorder you re-run when the flow changes.
#
# Usage (against a running dev server on :3000):
#   bin/rails server -p 3000   # in another shell
#   bin/rails runner test/demos/generate_report_demo.rb
#
# Output: public/demos/generate-report.webm
#
# Safe to run: it seeds a throwaway demo manager (demo@nykitchen.test), and dev
# mail goes nowhere real (delivery_method defaults to localhost SMTP, swallowed).
require "playwright"
require "fileutils"

abort "Run in development only" unless Rails.env.development?

HOST = ENV["DEMO_HOST"] || "http://localhost:3000"

# --- Seed a manager + NY Kitchen workspace + a snapshot with events ----------
manager = User.find_or_create_by!(email_address: "demo@nykitchen.test") { |u| u.role = "user" }
ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = manager }
ws.memberships.find_or_create_by!(user: manager) { |m| m.role = "admin" }

snapshot = KitchenSnapshot.find_or_create_by!(taken_on: Date.current)
if snapshot.kitchen_events.count.zero?
  names = [ "Knife Skills 101", "Fresh Pasta Workshop", "Sushi Rolling Night",
            "French Macarons", "Wood-Fired Pizza", "Thai Street Food",
            "Bread Baking Basics", "Steak & Wine Pairing", "Vegan Brunch",
            "Cake Decorating", "Tapas & Sangria", "Dumpling Masterclass" ]
  names.each_with_index do |name, i|
    cap = 12
    snapshot.kitchen_events.create!(
      url: "https://nykitchen.com/event/demo-#{i}", name: name,
      start_at: (i + 3).days.from_now, end_at: (i + 3).days.from_now + 2.hours,
      availability: "InStock", price: format("%.2f", 85 + (i % 5) * 15),
      capacity: cap, spots_left: [ cap - (i % cap), 0 ].max, venue: "NY Kitchen"
    )
  end
end
puts "Seeded manager=#{manager.id}, workspace=#{ws.slug}, snapshot=#{snapshot.taken_on} (#{snapshot.kitchen_events.count} events)"

# --- Drive + record ----------------------------------------------------------
cli       = Rails.root.join("node_modules", ".bin", "playwright").to_s
video_dir = Rails.root.join("tmp", "demos")
FileUtils.mkdir_p(video_dir)

Playwright.create(playwright_cli_executable_path: cli) do |pw|
  browser = pw.chromium.launch(headless: ENV["HEADFUL"] != "true" ? true : false)
  context = browser.new_context(viewport: { width: 1280, height: 860 }, record_video_dir: video_dir.to_s)
  # Dev login: POST sets the session cookie on the context.
  context.request.post("#{HOST}/dev/login_as/#{manager.id}")

  page = context.new_page
  page.goto("#{HOST}/nykitchen/analyst", timeout: 30_000, waitUntil: "networkidle")
  page.wait_for_selector("text=Need it now?", timeout: 15_000)
  page.wait_for_timeout(2_000)

  # Bring the Generate report card into view and click it.
  page.eval_on_selector("form[action*='report/generate']", "el => el.scrollIntoView({block: 'center'})")
  page.wait_for_timeout(1_500)
  page.click("form[action*='report/generate'] button")

  # Generate page: confirmation banner + the rendered report (the iframe is the
  # unambiguous "we're on the generate page now" signal).
  begin
    page.wait_for_selector("iframe[title='Team report preview']", timeout: 25_000)
  rescue => e
    shot = Rails.root.join("tmp", "demos", "debug.png")
    page.screenshot(path: shot.to_s) rescue nil
    puts "DEBUG url=#{page.url}"
    puts "DEBUG has_banner=#{page.content.include?('emailed to you')} has_iframe=#{page.content.include?('Team report preview')}"
    puts "DEBUG screenshot=#{shot}"
    raise e
  end
  page.wait_for_timeout(2_500)
  page.mouse.wheel(0, 500); page.wait_for_timeout(1_500)
  page.mouse.wheel(0, 700); page.wait_for_timeout(2_000)

  video_path = page.video.path
  context.close # finalizes the .webm
  browser.close

  dest = Rails.root.join("public", "demos", "generate-report.webm")
  FileUtils.mkdir_p(dest.dirname)
  FileUtils.mv(video_path, dest)
  puts "DEMO VIDEO SAVED: #{dest} (#{(File.size(dest) / 1024.0).round} KB)"
end
