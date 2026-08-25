require "test_helper"

# Workspace#social_path is the single source of truth for deep links to a
# workspace's Echo page: pushes, the daily email, and engagement alerts all use
# it. NY Kitchen keeps its vanity route; everyone else gets the generic one.
class WorkspaceSocialPathTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "ws-#{SecureRandom.hex(4)}@example.com", role: "admin")
  end

  test "NY Kitchen keeps its slug-baked vanity route" do
    nyk = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
    assert_equal "/nykitchen/social", nyk.social_path
  end

  test "every other workspace uses its own generic path" do
    ws = Workspace.create!(slug: "feastcoast-hospitality", name: "Feastcoast Hospitality", owner: @owner)
    assert_equal "/workspaces/feastcoast-hospitality/social", ws.social_path
  end
end
