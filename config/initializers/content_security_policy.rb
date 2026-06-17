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

  # No per-request nonce. 'unsafe-inline' above is what allows our inline
  # scripts (importmap tag, csp_meta_tag, javascript_tag blocks). Adding a
  # nonce to script-src is actively harmful here: a nonce makes the browser
  # IGNORE 'unsafe-inline', and Turbo Drive re-executes inline <script>s on
  # every navigation, stamping them with the *current* request's nonce. The
  # browser still enforces the nonce the document was first loaded with, so
  # those re-run scripts never match and get blocked — the console
  # "Executing inline script violates CSP / unsafe-inline is ignored" spam.
  # A stable nonce would need session.id, which is nil before the session
  # loads (that produced empty nonces that blocked everything — see git
  # history: the generator was added, broke, removed, re-added, broke again).
  # 'unsafe-inline' is the correct, consistent choice until we commit to a
  # strict nonce-only policy (drop 'unsafe-inline' + 'https:' and vendor the
  # CDN scripts), which is a separate project.

  # Report violations without enforcing initially — switch to enforcing after testing.
  # config.content_security_policy_report_only = true
end
