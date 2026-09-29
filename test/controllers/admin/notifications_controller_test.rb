require "test_helper"

class Admin::NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Notification.delete_all
    @admin  = User.create!(email_address: "notif-admin-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @lora   = User.create!(email_address: "notif-member-#{SecureRandom.hex(4)}@example.com", role: "user")
    @other  = User.create!(email_address: "notif-other-#{SecureRandom.hex(4)}@example.com", role: "user")
    sign_in_as(@admin)
  end

  # How broadcast_kitchen_alert fans out: one log copy + one per recipient.
  def broadcast(title)
    [ nil, @admin, @lora, @other ].map do |u|
      Notification.create!(level: "info", source: "kitchen_tickets", title: title, body: "a: 3 → 2", user: u)
    end
  end

  test "a broadcast alert shows once, not once per recipient" do
    broadcast("5 classes: 13 ticket(s) bought")

    get admin_notifications_path
    assert_response :success
    assert_equal 1, response.body.scan("5 classes: 13 ticket(s) bought").size
    assert_match "1 unread notification", response.body
  end

  test "mark all read leaves other people's copies unread" do
    broadcast("Sold out")

    post mark_all_read_admin_notifications_path
    assert Notification.where(user: [ nil, @admin ]).all?(&:read?)
    assert Notification.where(user: [ @lora, @other ]).none?(&:read?)
  end

  test "mark read and delete act on the alert's admin copies only" do
    log, mine, loras, _ = broadcast("One class")

    patch admin_notification_path(log)
    assert mine.reload.read?
    refute loras.reload.read?

    delete admin_notification_path(log)
    refute Notification.exists?(log.id)
    refute Notification.exists?(mine.id)
    assert Notification.exists?(loras.id)
  end

  test "another user's copy is not reachable from the admin page" do
    loras = broadcast("x")[2]
    delete admin_notification_path(loras)
    assert_response :not_found
    assert Notification.exists?(loras.id)
  end
end
