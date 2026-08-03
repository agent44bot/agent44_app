# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class BuzzCommandRouterTest < ActiveSupport::TestCase
  ALLOWED = "a" * 64
  STRANGER = "b" * 64

  setup do
    @router = Buzz::CommandRouter.new(logger: Logger.new(File::NULL))
    ENV["BUZZ_ALLOWED_PUBKEYS"] = ALLOWED
  end

  teardown do
    ENV.delete("BUZZ_ALLOWED_PUBKEYS")
    ENV.delete("BUZZ_PRIVATE_KEY")
  end

  def event(content, pubkey: ALLOWED)
    { "id" => SecureRandom.hex(32), "pubkey" => pubkey, "content" => content, "kind" => 1 }
  end

  test "ignores ordinary conversation" do
    assert_nil @router.call(event("should we run the smoke test later?"))
    assert_nil @router.call(event("!"))
    assert_nil @router.call(event(""))
  end

  test "answers help for an allowlisted pubkey" do
    assert_match(/!smoke/, @router.call(event("!help")))
  end

  test "refuses a command from a pubkey that is not allowlisted" do
    triggered = false

    SmokeDispatch.stub(:trigger!, ->(**) { triggered = true; :ok }) do
      assert_match(/not on the command allowlist/, @router.call(event("!smoke", pubkey: STRANGER)))
    end

    # The refusal is only meaningful if the dispatch genuinely never ran.
    assert_not triggered
  end

  test "refuses everything when the allowlist is unset, rather than allowing everything" do
    ENV.delete("BUZZ_ALLOWED_PUBKEYS")

    assert_match(/not on the command allowlist/, @router.call(event("!smoke")))
  end

  test "never answers a message signed by one of our own agents" do
    keypair = Buzz::Keypair.generate
    ENV["BUZZ_PRIVATE_KEY"] = keypair.private_key_hex

    # Even a valid command from ourselves is dropped, so replies cannot loop.
    assert_nil @router.call(event("!help", pubkey: keypair.public_key_hex))
  end

  test "reports smoke status from the most recent run" do
    SmokeTestRun.create!(name: "nyk_calendar_nav", status: "failed", started_at: 10.minutes.ago)

    reply = @router.call(event("!status"))

    assert_match(/nyk_calendar_nav/, reply)
    assert_match(/failed/, reply)
  end

  test "explains an unknown command instead of failing silently" do
    assert_match(/Unknown command !wat/, @router.call(event("!wat")))
  end

  test "triggers the smoke test through SmokeDispatch" do
    called = nil
    SmokeDispatch.stub(:trigger!, ->(requested_by:, via:) { called = { requested_by:, via: }; :ok }) do
      assert_match(/Kicked off/, @router.call(event("!smoke")))
    end

    assert_equal "Buzz", called[:via]
  end

  test "says so when the dispatch cannot run" do
    SmokeDispatch.stub(:trigger!, ->(**) { :no_token }) do
      assert_match(/GITHUB_PAT/, @router.call(event("!smoke")))
    end

    SmokeDispatch.stub(:trigger!, ->(**) { :failed }) do
      assert_match(/GitHub rejected/, @router.call(event("!smoke")))
    end
  end
end
