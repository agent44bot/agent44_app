# Tracks a user's in-flight (or just-finished) background grocery build so the
# app-wide navbar build bar can show progress and a link while they roam the app,
# exactly like a background recipe build. Backed by the shared cache (SolidCache
# in prod, so it is visible across puma workers / the separate navbar poll
# request). One build per user at a time is plenty: the grocery page shows one
# list at a time.
module GroceryBuildStatus
  BUILDING_TTL = 5.minutes # a build is ~30-60s; expire well after so a lost job clears
  DONE_TTL     = 2.minutes # keep the "ready" state briefly so the bar can link to it

  def self.key(user_id) = "grocery_build:#{user_id}"

  # Called when the page kicks off a build. token is the list's cache key, so a
  # later finish for a stale build never clobbers a newer one.
  def self.start(user_id:, token:, title:, url:)
    return unless user_id
    Rails.cache.write(key(user_id), { token: token, title: title, url: url, status: "building" }, expires_in: BUILDING_TTL)
  end

  # Called by the job when the build finishes. No-ops if a newer build has since
  # replaced this one (tokens differ), so the bar tracks the latest request.
  def self.finish(user_id:, token:, status:, error: nil)
    return unless user_id
    cur = Rails.cache.read(key(user_id))
    return unless cur && cur[:token] == token
    Rails.cache.write(key(user_id), cur.merge(status: status, error: error), expires_in: DONE_TTL)
  end

  def self.current(user_id)
    user_id && Rails.cache.read(key(user_id))
  end
end
