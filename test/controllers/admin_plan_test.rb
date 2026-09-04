require "test_helper"

# Owner-only /admin/plan: checkable plans (2027 growth is the default, June 2026 DBA on a tab).
class AdminPlanTest < ActionDispatch::IntegrationTest
  setup do
    Setting.delete_all
    @owner = User.find_or_create_by!(email_address: "botwhisperer@hey.com") { |u| u.role = "admin" }
    @owner.update!(role: "admin")
  end

  test "owner sees the 2027 growth plan by default" do
    sign_in_as(@owner)
    get admin_plan_path
    assert_response :success
    assert_match "2027 growth plan", response.body
    assert_match "Finish the multi-tenant refactor", response.body
    assert_match "Ask Lora for two warm intros", response.body
  end

  test "the June plan is still reachable on its tab" do
    sign_in_as(@owner)
    get admin_plan_path(plan: "june-2026")
    assert_response :success
    assert_match "June 2026 plan", response.body
    assert_match "File Certificate of Assumed Name", response.body
  end

  test "unknown plan slugs fall back to the default plan" do
    sign_in_as(@owner)
    get admin_plan_path(plan: "nope")
    assert_response :success
    assert_match "2027 growth plan", response.body
  end

  test "toggling a growth step is keyed per plan" do
    sign_in_as(@owner)
    post admin_plan_toggle_path(plan: "growth-2027", step_id: "multitenant")
    assert_redirected_to admin_plan_path(plan: "growth-2027")
    assert Setting.time("growth_2027:done:multitenant")
    assert_nil Setting.time("june_plan:done:multitenant")
  end

  test "a step id from another plan is rejected" do
    sign_in_as(@owner)
    post admin_plan_toggle_path(plan: "growth-2027", step_id: "ein")
    assert_response :unprocessable_entity
  end

  test "toggle without a plan keeps the legacy June key" do
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
