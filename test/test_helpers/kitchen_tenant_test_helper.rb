# The kitchen controllers resolve their tenant from the route and default to
# the NY Kitchen workspace (slug "nykitchen"). Tests that hit /nykitchen/* need
# that workspace to exist; kitchen records created afterwards default into it
# (see KitchenScoped).
module KitchenTenantTestHelper
  def nyk_workspace!(owner: nil, **attrs)
    Workspace.find_by(slug: Workspace::NYK_SLUG) ||
      Workspace.create!({ name: "NY Kitchen", slug: Workspace::NYK_SLUG, kitchen_enabled: true,
                          owner: owner || User.create!(email_address: "nyk-owner-#{SecureRandom.hex(4)}@example.com") }.merge(attrs))
  end
end

# Integration tests call kitchen helpers (nyk_list_path, nyk_scan_path(token))
# before any request has established a tenant. Route helpers in a test are
# delegated to the integration session, so default the segment there the same
# way ApplicationController#url_options does. After a request the session
# carries that request's controller url_options (its own slug) and this
# default steps aside.
module KitchenTenantSessionUrlOptions
  def url_options
    opts = super
    opts[:path_params] ? opts : opts.merge(path_params: { workspace_slug: Workspace::NYK_SLUG })
  end
end
ActionDispatch::Integration::Session.prepend(KitchenTenantSessionUrlOptions)
