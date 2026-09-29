require "test_helper"

class PageViewTest < ActiveSupport::TestCase
  test "online_user_ids returns only users with a page view inside the window" do
    recent, stale, idle = users(:one), users(:two), User.create!(email_address: "idle@example.com", password: "password123")
    PageView.create!(user: recent, path: "/", created_at: 1.minute.ago)
    PageView.create!(user: stale, path: "/", created_at: (PageView::ONLINE_WINDOW + 1.minute).ago)

    assert_equal Set[recent.id], PageView.online_user_ids([ recent.id, stale.id, idle.id ])
  end

  test "online_user_ids is empty for no ids" do
    assert_equal Set.new, PageView.online_user_ids([])
  end
end
