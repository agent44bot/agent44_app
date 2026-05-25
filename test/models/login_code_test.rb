require "test_helper"

class LoginCodeTest < ActiveSupport::TestCase
  test "issue! returns a 6-digit plaintext, normalizes email, stores only a digest" do
    record, code = LoginCode.issue!(email_address: "  Test@Example.com ")
    assert_match(/\A\d{6}\z/, code)
    assert_equal "test@example.com", record.email_address
    refute_equal code, record.code_digest
    assert record.authenticate_code(code)
  end

  test "issue! invalidates earlier unconsumed codes for the same email" do
    old, _ = LoginCode.issue!(email_address: "a@b.com")
    LoginCode.issue!(email_address: "a@b.com")
    assert old.reload.consumed?
    assert_equal 1, LoginCode.active.where(email_address: "a@b.com").count
  end

  test "verify succeeds for the right code and counts the attempt" do
    record, code = LoginCode.issue!(email_address: "a@b.com")
    assert record.verify(code)
    assert_equal 1, record.attempt_count
  end

  test "verify fails for a wrong code and still counts the attempt" do
    record, code = LoginCode.issue!(email_address: "a@b.com")
    wrong = code == "000000" ? "999999" : "000000"
    refute record.verify(wrong)
    assert_equal 1, record.attempt_count
  end

  test "verify locks out after MAX_ATTEMPTS, even with the right code" do
    record, code = LoginCode.issue!(email_address: "a@b.com")
    LoginCode::MAX_ATTEMPTS.times { record.verify("000000") }
    refute record.usable?
    refute record.verify(code), "correct code accepted past the attempt cap"
  end

  test "expired and consumed codes are unusable" do
    record, code = LoginCode.issue!(email_address: "a@b.com")
    record.update!(expires_at: 1.minute.ago)
    refute record.verify(code)

    record.update!(expires_at: 10.minutes.from_now, attempt_count: 0)
    record.consume!
    refute record.verify(code)
  end
end
