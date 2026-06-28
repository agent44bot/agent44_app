require "test_helper"

# PATCH /nykitchen/agents/:kind/avatar — workspace owner/admin sets or clears a
# bot's profile photo. Mirrors the rename_agent auth gate.
class KitchenAgentAvatarTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "av-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @workspace = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @admin }
    @workspace.memberships.find_or_create_by!(user: @admin) { |m| m.role = "admin" }
  end

  def upload
    fixture_file_upload("sample_bottle.png", "image/png")
  end

  test "admin uploads a bot photo" do
    sign_in_as(@admin)
    patch nyk_agent_avatar_path(kind: "list"), params: { avatar: upload }
    assert_redirected_to nykitchen_path
    assert @workspace.agent_for("list").avatar.attached?
  end

  test "remove clears the photo back to the stock avatar" do
    agent = @workspace.agent_for("list")
    agent.avatar.attach(io: file_fixture("sample_bottle.png").open, filename: "x.png", content_type: "image/png")
    sign_in_as(@admin)

    patch nyk_agent_avatar_path(kind: "list", remove: 1)
    assert_redirected_to nykitchen_path
    assert_not agent.reload.avatar.attached?
  end

  test "non-admin cannot change a bot photo" do
    sign_in_as(User.create!(email_address: "out-#{SecureRandom.hex(4)}@example.com", role: "user"))
    patch nyk_agent_avatar_path(kind: "list"), params: { avatar: upload }
    assert_redirected_to nykitchen_path
    assert_not @workspace.agent_for("list").avatar.attached?
  end

  test "unknown kind is rejected" do
    sign_in_as(@admin)
    patch nyk_agent_avatar_path(kind: "bogus"), params: { avatar: upload }
    assert_redirected_to nykitchen_path
    assert_equal "Unknown agent.", flash[:alert]
  end
end
