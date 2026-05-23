#!/usr/bin/env ruby
# One-shot: attach a build + set "What's New" on an ASC iOS App Store version.
# Usage:
#   ruby fastlane/finalize_version.rb <version_string> <build_number> "<whatsNew text>"
# Env: same as create_version.rb (APP_STORE_CONNECT_KEY_ID/ISSUER_ID/KEY_PATH).
require "spaceship"

version_string = ARGV[0] or abort "usage: ruby finalize_version.rb <version> <build_number> <whats_new>"
build_number   = ARGV[1] or abort "missing build number"
whats_new      = ARGV[2] or abort "missing whats_new copy"
bundle_id      = ENV["BUNDLE_ID"] || "com.agent44labs.app"

token = Spaceship::ConnectAPI::Token.create(
  key_id:    ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
  issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
  filepath:  File.expand_path(ENV.fetch("APP_STORE_CONNECT_KEY_PATH"))
)
Spaceship::ConnectAPI.token = token

app = Spaceship::ConnectAPI::App.find(bundle_id) or abort "App #{bundle_id} not found"
puts "App: #{app.name} (id=#{app.id})"

versions = app.get_app_store_versions(filter: { platform: "IOS" })
target = versions.find { |v| v.version_string == version_string }
abort "Version #{version_string} not found" unless target
puts "Version: #{target.version_string}  state=#{target.app_store_state}  id=#{target.id}"

builds = app.get_builds(filter: { "preReleaseVersion.platform" => "IOS", version: build_number })
build = builds.first
abort "Build #{build_number} not found for #{bundle_id}" unless build
puts "Build:   #{build.version} (#{build.pre_release_version&.version})  state=#{build.processing_state}  id=#{build.id}"

puts "Attaching build #{build_number} to version #{version_string}..."
Spaceship::ConnectAPI.patch_app_store_version_with_build(
  app_store_version_id: target.id,
  build_id: build.id
)
puts "  ✓ attached"

locs = Spaceship::ConnectAPI.get_app_store_version_localizations(app_store_version_id: target.id).to_models
en = locs.find { |l| l.locale == "en-US" } || abort("No en-US localization for #{version_string}")
puts "Localization en-US id=#{en.id}"

puts "Setting whatsNew (#{whats_new.length} chars)..."
Spaceship::ConnectAPI.patch_app_store_version_localization(
  app_store_version_localization_id: en.id,
  attributes: { whatsNew: whats_new }
)
puts "  ✓ whatsNew set"

puts "Done."
