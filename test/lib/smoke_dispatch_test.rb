# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The only way the app can cause a scrape: SiteGround CAPTCHAs Fly's IP, so the
# Mac mini runner does it and posts the snapshot back. These pin the request
# body, since a wrong client_payload silently runs the wrong tests.
class SmokeDispatchTest < ActiveSupport::TestCase
  setup { ENV["GITHUB_PAT"] = "test-token" }
  teardown { ENV.delete("GITHUB_PAT") }

  def capture_request
    sent = {}
    http = Object.new
    http.define_singleton_method(:use_ssl=) { |_| }
    http.define_singleton_method(:open_timeout=) { |_| }
    http.define_singleton_method(:read_timeout=) { |_| }
    http.define_singleton_method(:request) do |req|
      sent[:body] = JSON.parse(req.body)
      Struct.new(:code, :body).new("204", "")
    end
    Net::HTTP.stub(:new, http) { yield }
    sent
  end

  test "targets a single test via client_payload" do
    sent = capture_request { SmokeDispatch.trigger!(requested_by: "rich", via: "test", test: "scrape") }

    assert_equal "smoke-nyk", sent[:body]["event_type"]
    assert_equal "scrape", sent[:body].dig("client_payload", "test")
  end

  test "omits client_payload when no test is named, so the workflow runs them all" do
    sent = capture_request { SmokeDispatch.trigger!(requested_by: "rich", via: "test") }

    assert_equal "smoke-nyk", sent[:body]["event_type"]
    assert_not sent[:body].key?("client_payload")
  end

  test "ignores a test name the workflow does not offer" do
    sent = capture_request { SmokeDispatch.trigger!(requested_by: "rich", via: "test", test: "rm -rf") }

    assert_not sent[:body].key?("client_payload")
  end

  test "reports :no_token rather than pretending it dispatched" do
    ENV.delete("GITHUB_PAT")
    assert_equal :no_token, SmokeDispatch.trigger!(requested_by: "rich", via: "test", test: "scrape")
  end
end
