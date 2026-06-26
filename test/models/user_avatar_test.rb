require "test_helper"

class UserAvatarTest < ActiveSupport::TestCase
  def build_user(attrs = {})
    User.create!({ email_address: "a-#{SecureRandom.hex(4)}@example.com" }.merge(attrs))
  end

  test "initials use two letters for a multi-word display name" do
    assert_equal "LV", build_user(display_name: "Lora Vance").avatar_initials
  end

  test "initials fall back to the first letter of a single name or the email" do
    assert_equal "S", build_user(display_name: "Sam").avatar_initials
    assert_equal "Z", build_user(display_name: nil, email_address: "zoe-#{SecureRandom.hex(3)}@example.com").avatar_initials
  end

  test "avatar color classes are deterministic and drawn from the palette" do
    u = build_user
    assert_includes User::AVATAR_PALETTE, u.avatar_color_classes
    assert_equal u.avatar_color_classes, User.find(u.id).avatar_color_classes
  end

  test "accepts a valid image upload" do
    u = build_user
    u.avatar.attach(io: file_fixture("sample_bottle.png").open, filename: "a.png", content_type: "image/png")
    assert u.valid?
  end

  test "rejects a non-image upload" do
    u = build_user
    u.avatar.attach(io: StringIO.new("not an image"), filename: "a.txt", content_type: "text/plain")
    assert_not u.valid?
    assert_match(/PNG/, u.errors[:avatar].join)
  end
end
