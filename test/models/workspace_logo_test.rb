require "test_helper"

class WorkspaceLogoTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "wslogo-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "Logo WS", owner: @owner)
  end

  def attach_png
    @ws.logo.attach(io: File.open(Rails.root.join("test/fixtures/files/sample_bottle.png")),
                    filename: "logo.png", content_type: "image/png")
  end

  test "accepts a valid PNG logo" do
    attach_png
    assert @ws.valid?
    assert @ws.logo.attached?
  end

  test "rejects a non-image logo" do
    @ws.logo.attach(io: StringIO.new("not an image"), filename: "evil.txt", content_type: "text/plain")
    refute @ws.valid?
    assert_match(/PNG, JPEG, or WebP/, @ws.errors[:logo].join)
  end

  test "rejects a logo larger than 2 MB" do
    big = StringIO.new("x" * (Workspace::LOGO_MAX_BYTES + 1))
    @ws.logo.attach(io: big, filename: "big.png", content_type: "image/png")
    refute @ws.valid?
    assert_match(/2 MB/, @ws.errors[:logo].join)
  end

  test "a workspace with no logo is still valid" do
    assert @ws.valid?
    refute @ws.logo.attached?
  end
end
