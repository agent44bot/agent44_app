require "test_helper"

class WorkspaceInvitationTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "winv-o-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "WInv Test", owner: @owner)
  end

  test "auto-generates token + 14-day expiry on create" do
    inv = @ws.invitations.create!(invited_by: @owner, email: "x@example.com", role: "editor")
    assert inv.token.length >= 40
    assert_in_delta 14.days.from_now.to_i, inv.expires_at.to_i, 60
    assert inv.pending?
  end

  test "accept! creates a membership for the accepter and stamps accepted_at" do
    teammate = User.create!(email_address: "winv-t-#{SecureRandom.hex(4)}@example.com")
    inv = @ws.invitations.create!(invited_by: @owner, email: teammate.email_address, role: "editor")

    assert_difference -> { WorkspaceMembership.where(workspace_id: @ws.id, user_id: teammate.id).count }, 1 do
      inv.accept!(teammate)
    end
    assert inv.reload.accepted?
    assert_equal teammate.id, inv.accepted_by_id
    assert_equal "editor", @ws.role_for(teammate)
  end

  test "expired invitation cannot be accepted" do
    teammate = User.create!(email_address: "winv-e-#{SecureRandom.hex(4)}@example.com")
    inv = @ws.invitations.create!(invited_by: @owner, email: teammate.email_address, role: "editor")
    inv.update_columns(expires_at: 1.hour.ago)
    assert inv.expired?
    assert_raises(RuntimeError) { inv.accept!(teammate) }
  end

  test "revoked invitation cannot be accepted" do
    teammate = User.create!(email_address: "winv-r-#{SecureRandom.hex(4)}@example.com")
    inv = @ws.invitations.create!(invited_by: @owner, email: teammate.email_address, role: "editor")
    inv.revoke!
    assert inv.revoked?
    assert_raises(RuntimeError) { inv.accept!(teammate) }
  end

  test "two pending invitations for the same workspace+email are rejected" do
    @ws.invitations.create!(invited_by: @owner, email: "dup@example.com", role: "editor")
    second = @ws.invitations.build(invited_by: @owner, email: "dup@example.com", role: "editor")
    refute second.valid?
    assert_includes second.errors[:email], "already has a pending invitation"
  end
end
