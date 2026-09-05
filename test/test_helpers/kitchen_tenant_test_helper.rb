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
