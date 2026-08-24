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
    # form-action must list the OAuth providers' authorize hosts, not just
    # :self. The Connect buttons POST to our own /oauth/*/connect, which
    # answers with a 302 to the provider — and Chrome checks form-action
    # against the *redirect target*, then reports the violation using the
    # original (same-origin) URL, which makes the console error read as if
    # posting to ourselves were blocked. Without these hosts the connect
    # flow dies at the redirect with "violates ... form-action 'self'".
    # Both twitter.com and x.com are needed: X's authorize URL is on
    # twitter.com and can itself bounce to x.com mid-flow, and every hop is
    # checked. Threads and Facebook are listed so their flows work once
    # their credentials are configured.
    policy.form_action :self,
                       "https://twitter.com", "https://x.com",
                       "https://www.facebook.com", "https://facebook.com",
                       "https://threads.net", "https://www.threads.net"
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
