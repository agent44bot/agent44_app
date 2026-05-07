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
end
