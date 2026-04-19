# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    policy.script_src  :self, :https, :unsafe_inline
    policy.style_src   :self, :https, :unsafe_inline
    policy.connect_src :self, :https
    policy.frame_ancestors :none
    policy.base_uri    :self
    policy.form_action :self
  end

  # Generate a per-request nonce so inline scripts added by Rails helpers
  # (importmap tags, csp_meta_tag, javascript_tag nonce: true) are allowed.
  # Using SecureRandom instead of session.id — session.id can be nil before
  # the session is loaded, which produced empty nonces and broke everything.
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Report violations without enforcing initially — switch to enforcing after testing.
  # config.content_security_policy_report_only = true
end
