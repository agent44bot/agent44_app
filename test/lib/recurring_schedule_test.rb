require "test_helper"
require "fugit"

# Every schedule in config/recurring.yml must parse to a real recurrence
# (Fugit::Cron). A phrase like "every week on Monday at 4:41am" parses to a
# point in time (EtOrbi::EoTime) instead; SolidQueue's supervisor raises on
# it at boot and, running as a puma plugin, crash-loops prod (2026-06-05).
class RecurringScheduleTest < ActiveSupport::TestCase
  test "all recurring.yml schedules parse as crons" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml")) || {}
    entries = config.flat_map { |_env, jobs| (jobs || {}).map { |name, spec| [ name, spec["schedule"] ] } }
    assert entries.any?, "expected recurring.yml to define jobs"

    entries.each do |name, schedule|
      assert schedule.present?, "#{name}: missing schedule"
      parsed = Fugit.parse(schedule)
      assert_instance_of Fugit::Cron, parsed,
        "#{name}: #{schedule.inspect} parsed as #{parsed.class}, not a cron; SolidQueue will crash at boot"
    end
  end
end
