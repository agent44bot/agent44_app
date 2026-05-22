require "test_helper"

class WorkspaceAgentTest < ActiveSupport::TestCase
  setup do
    owner = User.create!(email_address: "wa-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @workspace = Workspace.create!(name: "WA Test", owner: owner)
  end

  test "setting falls back to DEFAULT_SETTINGS when key isn't persisted" do
    agent = @workspace.agent_for("display")
    agent.update!(settings: {})

    assert_equal 5,    agent.setting(:slide_count)
    assert_equal "public", agent.setting(:visibility)
    assert_equal true, agent.setting(:show_price)
    assert_equal false, agent.setting(:show_image)
  end

  test "setting returns persisted value when present (even falsy)" do
    agent = @workspace.agent_for("display")
    agent.update!(settings: { "slide_count" => 9, "show_price" => false })

    assert_equal 9,     agent.setting(:slide_count)
    assert_equal false, agent.setting(:show_price)
    assert_equal true,  agent.setting(:show_spots), "Untouched key falls back to default"
  end

  test "update_settings merges partial without clobbering other keys" do
    agent = @workspace.agent_for("display")
    agent.update!(settings: { "slide_count" => 7, "advance_seconds" => 15 })

    agent.update_settings(show_price: false)

    assert_equal 7,     agent.setting(:slide_count)
    assert_equal 15,    agent.setting(:advance_seconds)
    assert_equal false, agent.setting(:show_price)
  end

  test "rotate_share_token! generates a new token each call" do
    agent = @workspace.agent_for("display")
    t1 = agent.rotate_share_token!
    t2 = agent.rotate_share_token!

    assert t1.present?
    assert t2.present?
    refute_equal t1, t2, "Each rotation should generate a fresh token"
  end

  test "share_token_or_generate! returns existing token without rotating" do
    agent = @workspace.agent_for("display")
    first = agent.rotate_share_token!
    second = agent.share_token_or_generate!

    assert_equal first, second
  end

  test "share_token_or_generate! generates one when none exists" do
    agent = @workspace.agent_for("display")
    assert_nil agent.setting(:share_token)

    token = agent.share_token_or_generate!
    assert token.present?
    assert_equal token, agent.reload.setting(:share_token)
  end
end
