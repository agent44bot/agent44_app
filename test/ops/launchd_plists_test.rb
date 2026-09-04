require "test_helper"
require "rexml/document"

# The launchd plists in ops/launchd are the Mac mini's copy of the NYK smoke
# schedule. A malformed one loads as nothing (launchd fails silently), and a
# renamed script leaves a plist pointing at a path that no longer exists, so
# both failures look identical from here: the scrapes just stop.
class LaunchdPlistsTest < ActiveSupport::TestCase
  PLISTS = Dir[Rails.root.join("ops/launchd/*.plist")].sort

  test "every plist is well-formed and declares a Label" do
    assert PLISTS.any?, "expected ops/launchd to hold plists"

    PLISTS.each do |path|
      name = File.basename(path)
      doc = begin
        REXML::Document.new(File.read(path))
      rescue REXML::ParseException => e
        flunk "#{name} is not valid XML: #{e.message}"
      end

      keys = REXML::XPath.match(doc, "//key").map(&:text)
      assert_includes keys, "Label", "#{name} has no Label key"
      assert_includes keys, "ProgramArguments", "#{name} has no ProgramArguments key"
    end
  end

  test "every script a plist points at still exists" do
    PLISTS.each do |path|
      REXML::XPath.match(REXML::Document.new(File.read(path)), "//string").map(&:text).each do |arg|
        next unless arg.to_s.include?("agent44_app/bin/")

        script = Rails.root.join("bin", File.basename(arg))
        assert File.exist?(script),
               "#{File.basename(path)} runs #{arg}, but #{script.relative_path_from(Rails.root)} does not exist"
      end
    end
  end
end
