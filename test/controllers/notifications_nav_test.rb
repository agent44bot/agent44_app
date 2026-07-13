require "test_helper"

# The top nav should give every signed-in user a way to reach their
# Notifications page (bell icon on desktop, row in the mobile menu), with an
# unread-count badge.
class NotificationsNavTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws    = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
    @user  = User.create!(email_address: "mem-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws.memberships.find_or_create_by!(user: @user) { |m| m.role = "editor" }
    KitchenSnapshot.create!(taken_on: Date.current)
  end

  test "signed-in user's nav links to the notifications page" do
    sign_in_as(@user)
    get nykitchen_path
    assert_response :success
    assert_select "nav a[href=?]", notifications_path, { minimum: 1 }, "nav links to /notifications"
  end

  test "unread notifications show a count badge in the nav" do
    @user.notifications.create!(level: "info", source: "test", title: "Hi")
    @user.notifications.create!(level: "info", source: "test", title: "There")
    sign_in_as(@user)
    get nykitchen_path
    assert_response :success
    # The bell badge renders the unread count.
    assert_select "nav .notif-badge", text: "2", minimum: 1
  end

  test "no badge when everything is read" do
    @user.notifications.create!(level: "info", source: "test", title: "Old", read_at: Time.current)
    sign_in_as(@user)
    get nykitchen_path
    assert_response :success
    assert_select "nav a[href=?]", notifications_path
    assert_select "nav .notif-badge", count: 0
  end
end
