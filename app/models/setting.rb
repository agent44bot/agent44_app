class Setting < ApplicationRecord
  self.table_name = "kv_settings"

  validates :key, presence: true, uniqueness: true

  def self.get(key)
    find_by(key: key.to_s)&.value
  end

  def self.set(key, value)
    rec = find_or_initialize_by(key: key.to_s)
    rec.value = value.to_s
    rec.save!
    rec.value
  end

  def self.time(key)
    val = get(key)
    return nil if val.blank?
    Time.zone.parse(val)
  rescue ArgumentError
    nil
  end

  def self.touch_time(key)
    set(key, Time.current.iso8601)
  end

  def self.delete_key(key)
    where(key: key.to_s).delete_all
  end

  # Read an integer counter (0 when unset).
  def self.counter(key)
    get(key).to_i
  end

  # Atomically bump an integer counter and return the new value. Upsert + SQL
  # increment so concurrent bumps don't lose counts.
  def self.increment(key, by = 1)
    key = key.to_s
    find_or_create_by!(key: key) { |r| r.value = "0" } unless exists?(key: key)
    where(key: key).update_all("value = CAST(COALESCE(value, '0') AS INTEGER) + #{by.to_i}")
    counter(key)
  end
end
