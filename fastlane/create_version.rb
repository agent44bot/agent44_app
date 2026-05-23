#!/usr/bin/env ruby
# One-shot: create a new ASC iOS App Store version draft.
# Usage: APP_STORE_CONNECT_KEY_ID=... APP_STORE_CONNECT_ISSUER_ID=... \
#        APP_STORE_CONNECT_KEY_PATH=... ruby fastlane/create_version.rb 1.0.1
require "spaceship"

new_version = ARGV[0] or abort "usage: ruby create_version.rb <version-string>"
bundle_id   = ENV["BUNDLE_ID"] || "com.agent44labs.app"

token = Spaceship::ConnectAPI::Token.create(
  key_id:    ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
  issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
  filepath:  File.expand_path(ENV.fetch("APP_STORE_CONNECT_KEY_PATH"))
)
Spaceship::ConnectAPI.token = token

app = Spaceship::ConnectAPI::App.find(bundle_id) or abort "App #{bundle_id} not found"
puts "App: #{app.name} (id=#{app.id})"

existing = app.get_app_store_versions(filter: { platform: "IOS" }, includes: nil)
puts "Existing iOS versions:"
existing.each { |v| puts "  - #{v.version_string}  state=#{v.app_store_state}" }

if existing.any? { |v| v.version_string == new_version }
  puts "Version #{new_version} already exists — nothing to do."
  exit 0
end

puts "Creating iOS version #{new_version}..."
resp = Spaceship::ConnectAPI.post_app_store_version(
  app_id: app.id,
  attributes: {
    versionString: new_version,
    platform:      "IOS",
    releaseType:   "MANUAL"
  }
)
data = resp.body["data"] || resp.body
puts "Created: id=#{data["id"]}  attrs=#{(data["attributes"] || {}).slice("versionString", "appStoreState", "platform").inspect}"
