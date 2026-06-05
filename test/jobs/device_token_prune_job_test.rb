require "test_helper"

class DeviceTokenPruneJobTest < ActiveJob::TestCase
  setup do
    DeviceToken.delete_all
    @user = User.create!(email_address: "prune-#{SecureRandom.hex(4)}@example.com", role: "user")
  end

  def token!(active:, user: nil, age: 0.days)
    t = DeviceToken.create!(token: SecureRandom.hex(32), platform: "ios", active: active, user: user)
    t.update_column(:updated_at, age.ago)
    t
  end

  test "destroys inactive tokens stale for 30+ days" do
    dead    = token!(active: false, age: 31.days)
    recent  = token!(active: false, age: 5.days)
    DeviceTokenPruneJob.perform_now
    assert_not DeviceToken.exists?(dead.id)
    assert DeviceToken.exists?(recent.id), "recently deactivated token should survive (might be a 410 blip)"
  end

  test "deactivates orphans idle for 90+ days" do
    idle_orphan   = token!(active: true, age: 91.days)
    fresh_orphan  = token!(active: true, age: 10.days)
    DeviceTokenPruneJob.perform_now
    assert_not idle_orphan.reload.active
    assert fresh_orphan.reload.active
  end

  test "never touches linked active tokens regardless of age" do
    old_linked = token!(active: true, user: @user, age: 200.days)
    DeviceTokenPruneJob.perform_now
    assert old_linked.reload.active
    assert DeviceToken.exists?(old_linked.id)
  end
end
