namespace :test do
  desc "Run production smoke tests via bin/smoke (hits live endpoints)"
  task :smoke do
    filter = ARGV[1]
    cmd = filter ? "bin/smoke #{filter}" : "bin/smoke"
    exec cmd
  end

  namespace :smoke do
    desc "NY Kitchen calendar arrow-nav smoke test (Playwright, email preview on fail)"
    task :nyk do
      ENV["RUN_SMOKE"] = "true"
      exec "bin/rails test test/smoke/nyk_calendar_nav_test.rb"
    end
  end
end
