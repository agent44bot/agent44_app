require "test_helper"
require "ostruct"
require "minitest/mock"

class AiCallLoggerTest < ActiveSupport::TestCase
  test "log! creates an AiCallLog row from an SDK-style response with .usage" do
    response = OpenStruct.new(usage: OpenStruct.new(input_tokens: 1234, output_tokens: 567))

    assert_difference -> { AiCallLog.count }, 1 do
      AiCallLogger.log!(response, model: "claude-haiku-4-5-20251001", source: "nyk_enhance")
    end

    log = AiCallLog.last
    assert_equal "claude-haiku-4-5-20251001", log.model
    assert_equal "nyk_enhance",                log.source
    assert_equal 1234, log.input_tokens
    assert_equal 567,  log.output_tokens
    assert_nil log.user_id
  end

  test "log! attaches the user when supplied" do
    user = User.create!(email_address: "logger-test-#{SecureRandom.hex(4)}@example.com", role: "admin")
    response = OpenStruct.new(usage: OpenStruct.new(input_tokens: 10, output_tokens: 20))

    AiCallLogger.log!(response, model: "claude-haiku-4-5-20251001", source: "nyk_enhance", user: user)

    assert_equal user.id, AiCallLog.last.user_id
  end

  test "log! returns nil and does not raise when response has no usage" do
    response = OpenStruct.new(content: [])

    assert_no_difference -> { AiCallLog.count } do
      result = AiCallLogger.log!(response, model: "claude-haiku-4-5-20251001", source: "nyk_enhance")
      assert_nil result
    end
  end

  test "log! swallows persistence errors so it never breaks the caller" do
    response = OpenStruct.new(usage: OpenStruct.new(input_tokens: 10, output_tokens: 20))

    AiCallLog.stub :create!, ->(*) { raise ActiveRecord::RecordInvalid.new(AiCallLog.new) } do
      assert_nothing_raised do
        AiCallLogger.log!(response, model: "claude-haiku-4-5-20251001", source: "nyk_enhance")
      end
    end
  end

  test "log! supports a Hash response (e.g. legacy/raw payload)" do
    response = { usage: { input_tokens: 50, output_tokens: 25 } }

    AiCallLogger.log!(response, model: "claude-haiku-4-5-20251001", source: "nyk_x_autopost")

    log = AiCallLog.last
    assert_equal 50, log.input_tokens
    assert_equal 25, log.output_tokens
  end
end
