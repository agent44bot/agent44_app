# Weekly device-token hygiene. Two tiers:
#
#   1. DESTROY tokens that are already inactive (deactivated by an APNs 410
#      or by hand) and stale for 30+ days -- they are dead identities, and
#      keeping them only clutters debugging (see the 2026-06-05 push hunt,
#      where 24 rows hid which one was the iPhone).
#   2. DEACTIVATE orphan tokens (no user) not re-registered in 90+ days.
#      Live apps re-post their token on every launch, so a quiet orphan is
#      almost certainly an uninstalled or wiped device. Deactivating (not
#      destroying) keeps it revivable if the device ever comes back.
#
# Linked, active tokens are never touched here regardless of age: a signed-in
# device that never reopens the app still gets pushes until APNs 410s it.
class DeviceTokenPruneJob < ApplicationJob
  queue_as :default

  DESTROY_INACTIVE_AFTER = 30.days
  ORPHAN_IDLE_AFTER      = 90.days

  def perform
    destroyed = DeviceToken.where(active: false)
      .where(updated_at: ...DESTROY_INACTIVE_AFTER.ago)
      .destroy_all.size

    idled = DeviceToken.where(active: true, user_id: nil)
      .where(updated_at: ...ORPHAN_IDLE_AFTER.ago)
      .update_all(active: false, updated_at: Time.current)

    Rails.logger.info("DeviceTokenPruneJob: destroyed #{destroyed} dead, idled #{idled} stale orphans")
  end
end
