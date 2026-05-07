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
    @far_future_event = @snapshot.kitchen_events.create!(
      url:          "https://nykitchen.com/event/x-job-far-#{SecureRandom.hex(2)}/",
      name:         "Far-Future Class",
      description:  "Outside the lookahead window",
      start_at:     60.days.from_now,
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

  test "pick_event ignores classes past the 14-day lookahead window" do
    job = PostNykClassToXJob.new
    picked = job.send(:pick_event, @snapshot)
    assert_includes [@event.url], picked&.url
    refute_equal @far_future_event.url, picked&.url
  end

  test "X_AUTOPOST_LOOKAHEAD_DAYS env override widens the window" do
    ENV["X_AUTOPOST_LOOKAHEAD_DAYS"] = "90"
    begin
      # With a 90-day window, both the 3-day and 60-day events are eligible.
      job = PostNykClassToXJob.new
      30.times do
        log = SocialPostLog.find_or_initialize_by(event_url: SecureRandom.hex(8))
        log.x_drafted_at = nil
        log.save!
      end
      picked_urls = 20.times.map { job.send(:pick_event, @snapshot)&.url }.compact.uniq
      assert_includes picked_urls, @far_future_event.url
    ensure
      ENV.delete("X_AUTOPOST_LOOKAHEAD_DAYS")
    end
  end
end
