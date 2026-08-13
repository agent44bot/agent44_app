require "test_helper"

# The login-free unsubscribe link in Echo's daily email.
class EchoEmailSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @ws = Workspace.create!(slug: "echo-unsub-#{SecureRandom.hex(3)}", name: "Test Kitchen", owner: @user)
    @membership = @ws.memberships.find_by!(user: @user) # created with the workspace
    @token = @membership.echo_unsubscribe_token
  end

  test "GET confirms without signing in and changes nothing yet" do
    get echo_email_unsubscribe_path(@token)

    assert_response :success
    assert_match "Turn off Echo emails?", response.body
    assert @membership.reload.echo_email_enabled, "a prefetched GET must not mute anyone"
  end

  test "POST turns the email off" do
    post echo_email_unsubscribe_path(@token)

    assert_response :success
    assert_not @membership.reload.echo_email_enabled
  end

  test "a tampered token is rejected" do
    post echo_email_unsubscribe_path("#{@token}tampered")

    assert_response :not_found
    assert @membership.reload.echo_email_enabled
  end

  test "a token only ever turns off its own membership" do
    other_user = users(:two)
    other = @ws.memberships.create!(user: other_user, role: "editor")

    post echo_email_unsubscribe_path(@token)

    assert_not @membership.reload.echo_email_enabled
    assert other.reload.echo_email_enabled
  end

  test "a signed-in member lands on the page instead of being bounced to /workspaces" do
    sign_in_as @user

    get echo_email_unsubscribe_path(@token)

    assert_response :success
  end
end
