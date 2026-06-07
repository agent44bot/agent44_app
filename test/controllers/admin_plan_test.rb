require "test_helper"

# Owner-only /admin/plan: the checkable June to-do list.
class AdminPlanTest < ActionDispatch::IntegrationTest
  setup do
    Setting.delete_all
    @owner = User.find_or_create_by!(email_address: "botwhisperer@hey.com") { |u| u.role = "admin" }
    @owner.update!(role: "admin")
  end

  test "owner sees the plan with progress" do
    sign_in_as(@owner)
    get admin_plan_path
    assert_response :success
    assert_match "June 2026 plan", response.body
    assert_match "File Certificate of Assumed Name", response.body
  end

  test "toggle marks a step done and untoggle clears it" do
    sign_in_as(@owner)
    post admin_plan_toggle_path(step_id: "ein")
    assert Setting.time("june_plan:done:ein"), "step should be timestamped"
    post admin_plan_toggle_path(step_id: "ein")
    assert_nil Setting.time("june_plan:done:ein")
  end

  test "unknown step ids are rejected" do
    sign_in_as(@owner)
    post admin_plan_toggle_path(step_id: "nope")
    assert_response :unprocessable_entity
  end

  test "non-owner admins are redirected" do
    other = User.create!(email_address: "np-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(other)
    get admin_plan_path
    assert_redirected_to root_path
  end
end
