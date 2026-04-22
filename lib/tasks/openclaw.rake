desc "Show the OpenClaw playbook"
task :openclaw do
  puts <<~PLAYBOOK

    ╔════════════════════════════════════════════════════════════════════╗
    ║                    OpenClaw agent playbook                        ║
    ╠════════════════════════════════════════════════════════════════════╣
    ║  All tasks below route through OpenClaw agents (costs tokens)     ║
    ╚════════════════════════════════════════════════════════════════════╝

      rake openclaw:deploy   → Knox deploys agent44-app (Haiku tokens)
      rake openclaw:test     → Vlad runs system tests (Haiku tokens)
      rake openclaw:smoke    → Scout runs NYK smoke test (Haiku tokens)

  PLAYBOOK
end

namespace :openclaw do
  desc "Knox deploys agent44-app via OpenClaw (costs Haiku tokens)"
  task :deploy do
    abort "✗ openclaw CLI not found" unless system("which openclaw > /dev/null 2>&1")
    commit = `git rev-parse --short HEAD`.strip
    exec "openclaw agent --agent knox " \
         "--message \"Deploy agent44-app to prod (commit #{commit}). " \
         "Run: cd #{Dir.pwd} && git pull --ff-only && fly deploy. " \
         "Report stdout/exit code.\" --json --timeout 600"
  end

  desc "Vlad runs system tests via OpenClaw (costs Haiku tokens)"
  task :test do
    abort "✗ openclaw CLI not found" unless system("which openclaw > /dev/null 2>&1")
    exec "openclaw agent --agent vlad " \
         "--message \"Run Playwright system tests for agent44-app. " \
         "Run: cd #{Dir.pwd} && ruby -Itest test/system/nykitchen_test.rb --verbose. " \
         "Report results.\" --json --timeout 300"
  end

  desc "Scout runs NYK smoke test via OpenClaw (costs Haiku tokens)"
  task :smoke do
    abort "✗ openclaw CLI not found" unless system("which openclaw > /dev/null 2>&1")
    exec "openclaw agent --agent scout " \
         "--message \"Run the NY Kitchen calendar smoke test. " \
         "Run: cd #{Dir.pwd} && RUN_SMOKE=true bin/rails test test/smoke/nyk_calendar_nav_test.rb. " \
         "Report results.\" --json --timeout 600"
  end
end
