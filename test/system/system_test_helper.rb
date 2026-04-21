ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "rails/test_help"
require "playwright"
require "net/http"
require "fileutils"

# System tests use Playwright against a local Rails server on port 3001.
# The test DB is seeded from a production snapshot before the server boots.
#
# Refresh the seed from production:
#   fly ssh console -C "sqlite3 /data/production.sqlite3 .dump" > /tmp/prod.sql
#   rm -f storage/test_seed.sqlite3 && sqlite3 storage/test_seed.sqlite3 < /tmp/prod.sql
class SystemTestCase < ActiveSupport::TestCase
  self.use_transactional_tests = false

  SERVER_PORT = 3001
  BASE_URL = "http://localhost:#{SERVER_PORT}"
  SEED_DB = Rails.root.join("storage/test_seed.sqlite3")
  TEST_DB = Rails.root.join("storage/test.sqlite3")

  class << self
    attr_accessor :server_pid, :playwright_exec, :browser
  end

  setup do
    self.class.boot! unless self.class.server_pid
    @page = self.class.browser.new_page
  end

  teardown do
    @page&.close
  end

  def self.boot!
    # Reset test DB from production seed before booting server
    if SEED_DB.exist?
      FileUtils.cp(SEED_DB, TEST_DB)
      system("RAILS_ENV=test bin/rails db:migrate > /dev/null 2>&1")
    end

    self.server_pid = spawn(
      { "RAILS_ENV" => "test", "PORT" => SERVER_PORT.to_s },
      "bin/rails", "server", "-p", SERVER_PORT.to_s,
      out: "/dev/null", err: "/dev/null"
    )

    30.times do
      break if Net::HTTP.get(URI("#{BASE_URL}/up")) rescue nil
      sleep 0.5
    end

    self.playwright_exec = Playwright.create(playwright_cli_executable_path: "npx playwright")
    headless = ENV["HEADED"] != "true"
    self.browser = playwright_exec.playwright.chromium.launch(headless: headless, slowMo: headless ? 0 : 300)
  end

  def self.shutdown
    browser&.close
    playwright_exec&.stop
    if server_pid
      Process.kill("TERM", server_pid) rescue nil
      Process.wait(server_pid) rescue nil
    end
  end

  Minitest.after_run { SystemTestCase.shutdown }
end
