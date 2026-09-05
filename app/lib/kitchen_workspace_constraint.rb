# Route constraint for the kitchen feature set mounted at /:workspace_slug/*.
# Matches only kitchen-enabled workspace slugs (NY Kitchen always, so its
# permanent URLs never depend on the flag), so the dynamic scope can never
# shadow a top-level route like /jobs. Slugs are cached briefly; Workspace
# busts the cache when a slug or the kitchen flag changes.
class KitchenWorkspaceConstraint
  CACHE_KEY = "kitchen_workspace_slugs".freeze

  def self.slugs
    Rails.cache.fetch(CACHE_KEY, expires_in: 5.minutes) do
      (Workspace.kitchen.pluck(:slug) + [ Workspace::NYK_SLUG ]).uniq
    end
  rescue ActiveRecord::StatementInvalid
    # Pre-migration boot (e.g. db:prepare on a fresh DB) must not crash routing.
    [ Workspace::NYK_SLUG ]
  end

  def self.slug?(slug) = slugs.include?(slug.to_s)
  def self.reset! = Rails.cache.delete(CACHE_KEY)

  def matches?(request)
    self.class.slug?(request.path_parameters[:workspace_slug])
  end
end
