class KitchenTicketDigest < ApplicationRecord
  belongs_to :kitchen_snapshot

  scope :recent, -> { order(created_at: :desc) }

  # entries: [{ "url" => "...", "name" => "...", "old_spots" => N, "new_spots" => N,
  #            "tickets_bought" => N, "sold_out" => true|false,
  #            "week_index" => N, "week_label" => "Current Week" }, ...]
  def entry_records
    Array(entries).map { |c| c.is_a?(Hash) ? c.with_indifferent_access : c }
  end

  def entries_by_week
    entry_records.group_by { |c| [ c["week_index"].to_i, c["week_label"] ] }
                 .sort_by { |(idx, _label), _| idx }
  end
end
