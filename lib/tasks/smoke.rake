desc "Show the smoke test playbook"
task :smoke do
  puts <<~PLAYBOOK

    ╔════════════════════════════════════════════════════════════════════╗
    ║                    agent44_app smoke test playbook                ║
    ╚════════════════════════════════════════════════════════════════════╝

      rake smoke:all         → run all smoke tests
      rake smoke:nyk         → NY Kitchen calendar smoke test (Playwright)
      rake openclaw:smoke    → Scout runs smoke via OpenClaw (Haiku tokens)

  PLAYBOOK
end

namespace :smoke do
  desc "Run all production smoke tests via bin/smoke"
  task :all do
    exec "bin/smoke"
  end

  desc "NY Kitchen calendar smoke tests (Playwright, email on fail)"
  task :nyk do
    ENV["RUN_SMOKE"] = "true"
    exec "bin/rails test test/smoke/nyk_calendar_nav_test.rb test/smoke/nyk_list_nav_test.rb test/smoke/nyk_coupon_field_test.rb"
  end
end

# Keep test:smoke and test:smoke:nyk as aliases for backwards compatibility
namespace :test do
  desc "Run production smoke tests via bin/smoke (hits live endpoints)"
  task smoke: "smoke:all"

  namespace :smoke do
    desc "NY Kitchen calendar arrow-nav smoke test (Playwright, email preview on fail)"
    task nyk: "smoke:nyk"
  end
end
