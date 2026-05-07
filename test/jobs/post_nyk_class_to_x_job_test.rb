require "test_helper"
require "ostruct"
require "minitest/mock"

# Daily X autopost cron — verifies the AI call site logs token usage.
# Anthropic::Client is stubbed; XClient is not exercised because the job
# never posts to X (only drafts).
class PostNykClassToXJobTest < ActiveJob::TestCase
  setup do
    ENV["X_AUTOPOST_ENABLED"]  = "true"
    ENV["ANTHROPIC_API_KEY"]   = "test-key"

    @snapshot = KitchenSnapshot.create!(taken_on: Date.today)
    @event = @snapshot.kitchen_events.create!(
      url:          "https://nykitchen.com/event/x-job-test-#{SecureRandom.hex(2)}/",
      name:         "X Autopost Test Class",
      description:  "A class to test the autopost job",
      start_at:     3.days.from_now,
      availability: "InStock"
    )
  end

  teardown do
    ENV.delete("X_AUTOPOST_ENABLED")
    ENV.delete("ANTHROPIC_API_KEY")
  end

  test "writes an ai_call_logs row with source nyk_x_autopost" do
    text_block = OpenStruct.new(text: "Tweet body about #{@event.name}")
    fake_response = OpenStruct.new(
      content: [text_block],
      usage:   OpenStruct.new(input_tokens: 200, output_tokens: 60)
    )
    fake_messages = OpenStruct.new
    fake_messages.define_singleton_method(:create) { |**| fake_response }
    fake_client = OpenStruct.new(messages: fake_messages)

    Anthropic::Client.stub :new, ->(**) { fake_client } do
      assert_difference -> { AiCallLog.count }, 1 do
        PostNykClassToXJob.new.perform
      end
    end

    log = AiCallLog.last
    assert_equal "claude-haiku-4-5-20251001", log.model
    assert_equal "nyk_x_autopost",             log.source
    assert_equal 200, log.input_tokens
    assert_equal 60,  log.output_tokens
  end

  test "no log row when killswitch is off" do
    ENV["X_AUTOPOST_ENABLED"] = "false"

    assert_no_difference -> { AiCallLog.count } do
      PostNykClassToXJob.new.perform
    end
  end
end
