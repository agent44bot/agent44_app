require "test_helper"

class ResolveDisplayLocationJobTest < ActiveJob::TestCase
  # Pre-seed the geo cache so the job never hits the external ip-api service
  # (house rule: tests never call an external API). The test env uses a
  # null_store, so swap in a real MemoryStore for the cache hit to stick.
  test "writes the located City, ST to the display city setting" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write("nyk_display_geo:8.8.8.8", "Rochester, NY")
    ResolveDisplayLocationJob.perform_now("8.8.8.8")
    assert_equal "Rochester, NY", Setting.get("nyk_display:city")
  ensure
    Rails.cache = original
  end

  test "skips private and blank IPs without touching the setting or the network" do
    ResolveDisplayLocationJob.perform_now("192.168.1.5")
    ResolveDisplayLocationJob.perform_now("")
    assert_nil Setting.get("nyk_display:city")
  end
end
