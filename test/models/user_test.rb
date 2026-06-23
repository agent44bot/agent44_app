require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "push_enabled_for_workspace? allows a nil workspace and non-members" do
    member = User.create!(email_address: "pw-#{SecureRandom.hex(4)}@example.com")
    ws = Workspace.create!(name: "WS", slug: "pw-#{SecureRandom.hex(4)}", owner_id: member.id)
    stranger = User.create!(email_address: "pw-#{SecureRandom.hex(4)}@example.com")

    assert member.push_enabled_for_workspace?(nil), "nil workspace = allowed"
    assert stranger.push_enabled_for_workspace?(ws), "non-member has no pref = allowed"
  end

  test "push_enabled_for_workspace? follows the membership's push_enabled flag" do
    owner = User.create!(email_address: "pw-#{SecureRandom.hex(4)}@example.com")
    ws = Workspace.create!(name: "WS", slug: "pw-#{SecureRandom.hex(4)}", owner_id: owner.id)

    assert owner.push_enabled_for_workspace?(ws), "defaults to on"
    ws.memberships.find_by(user_id: owner.id).update!(push_enabled: false)
    refute owner.reload.push_enabled_for_workspace?(ws), "muted workspace"
  end
end
