namespace :test do
  desc "Run Playwright system tests (headless, Vlad status updates)"
  task :system do
    vlad_status "busy", "Running system tests (headless)"
    success = system("ruby -Itest test/system/nykitchen_test.rb --verbose")
    vlad_status(success ? "online" : "error", success ? "System tests passed" : "System tests failed")
    exit(1) unless success
  end

  namespace :system do
    desc "Run Playwright system tests in headed browser (visible, Vlad status updates)"
    task :headed do
      vlad_status "busy", "Running system tests (headed browser)"
      success = system("HEADED=true ruby -Itest test/system/nykitchen_test.rb --verbose")
      vlad_status(success ? "online" : "error", success ? "System tests passed" : "System tests failed")
      exit(1) unless success
    end
  end
end

def vlad_status(status, task = "")
  script = File.expand_path("~/.openclaw/skills/update-agent-status.sh")
  system("bash", script, "Vlad ✅", status, task) if File.exist?(script)
end
