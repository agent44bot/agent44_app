require "test_helper"

# Admin "view-as" impersonation:
#   - POST /impersonate/:user_id starts; admin's session row gets
#     impersonated_user_id set, Current.user resolves to the target,
#     Current.real_user keeps pointing at the admin.
#   - DELETE /impersonate stops; impersonated_user_id is cleared.
#   - Non-admins cannot impersonate. Admins cannot impersonate other admins.
#   - Destructive settings actions are blocked mid-impersonation.
#   - Every start and stop writes an ImpersonationLog row.
class ImpersonationTest < ActionDispatch::IntegrationTest
  setup do
    @admin   = User.create!(email_address: "imp-admin-#{SecureRandom.hex(4)}@example.com",   role: "admin")
    @other_admin = User.create!(email_address: "imp-admin2-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @target  = User.create!(email_address: "imp-target-#{SecureRandom.hex(4)}@example.com",  role: "user", display_name: "Imp Target")
    @bystander = User.create!(email_address: "imp-by-#{SecureRandom.hex(4)}@example.com",    role: "user")
  end

  test "admin can start impersonating a non-admin user" do
    sign_in_as(@admin)
    assert_difference -> { ImpersonationLog.where(event: "start").count }, +1 do
      post impersonate_path(user_id: @target.id)
    end
    assert_redirected_to root_path
    assert_equal @target.id, Current.session.reload.impersonated_user_id
    assert Current.session.impersonating?
    assert_equal @target.id, Current.session.effective_user.id
    assert_equal @admin.id,  Current.session.user.id
  end

  test "stop impersonating clears the impersonated_user_id and writes a log row" do
    sign_in_as(@admin)
    post impersonate_path(user_id: @target.id)
    assert_difference -> { ImpersonationLog.where(event: "stop").count }, +1 do
      delete stop_impersonating_path
    end
    assert_nil Current.session.reload.impersonated_user_id
    refute Current.session.impersonating?
  end

  test "non-admin cannot impersonate anyone" do
    sign_in_as(@bystander)
    assert_no_difference -> { ImpersonationLog.count } do
      post impersonate_path(user_id: @target.id)
    end
    assert_redirected_to root_path
    assert_nil Current.session.reload.impersonated_user_id
  end

  test "admin cannot impersonate another admin" do
    sign_in_as(@admin)
    assert_no_difference -> { ImpersonationLog.count } do
      post impersonate_path(user_id: @other_admin.id)
    end
    assert_nil Current.session.reload.impersonated_user_id
  end

  test "account-deletion is blocked while impersonating" do
    sign_in_as(@admin)
    post impersonate_path(user_id: @target.id)
    assert_no_difference -> { User.count } do
      delete settings_path, params: { password: "anything" }
    end
    assert User.exists?(@target.id), "target must not have been deleted"
  end

  test "email change is blocked while impersonating" do
    @target.update!(password: "OriginalPwd1!", password_confirmation: "OriginalPwd1!")
    original_email = @target.email_address
    sign_in_as(@admin)
    post impersonate_path(user_id: @target.id)
    patch update_email_settings_path, params: { password: "OriginalPwd1!", email_address: "hijack-#{SecureRandom.hex(4)}@example.com" }
    assert_equal original_email, @target.reload.email_address, "email must not have been changed"
  end
end
