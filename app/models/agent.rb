class Agent < ApplicationRecord
  STATUSES = %w[online busy error offline].freeze
  COLORS = %w[orange amber green blue purple red cyan].freeze

  # An agent's busy/error state is only trusted while it keeps refreshing
  # last_active_at. After this window the stored state is treated as stale
  # and the agent is shown as online — so a forgotten status update from
  # OpenClaw/Knox can't pin the dashboard indefinitely.
  STALE_AFTER = 5.minutes

  validates :name, presence: true, uniqueness: true
  validates :role, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :avatar_color, inclusion: { in: COLORS }

  scope :ordered, -> {
    order(
      Arel.sql("CASE status WHEN 'busy' THEN 0 WHEN 'error' THEN 1 ELSE 2 END"),
      Arel.sql("COALESCE(last_active_at, '1970-01-01') DESC"),
      :position, :name
    )
  }
  scope :active, -> { where.not(status: "offline") }

  def effective_status
    return status unless %w[busy error].include?(status)
    return status unless last_active_at.present?
    last_active_at < STALE_AFTER.ago ? "online" : status
  end

  def online?  = effective_status == "online"
  def busy?    = effective_status == "busy"
  def error?   = effective_status == "error"
  def offline? = effective_status == "offline"

  def initials
    name[0].upcase
  end

  def status_color
    case effective_status
    when "online" then "green"
    when "busy"   then "amber"
    when "error"  then "red"
    else "gray"
    end
  end

  def status_label
    case effective_status
    when "busy"  then current_task.presence || "Working on a task"
    when "error" then current_task.presence || "Task failed"
    else effective_status.capitalize
    end
  end

  AVATAR_BG_CLASSES = {
    "orange" => "bg-orange-900/50",
    "amber"  => "bg-amber-900/50",
    "green"  => "bg-green-900/50",
    "blue"   => "bg-blue-900/50",
    "purple" => "bg-purple-900/50",
    "red"    => "bg-red-900/50",
    "cyan"   => "bg-cyan-900/50"
  }.freeze

  AVATAR_TEXT_CLASSES = {
    "orange" => "text-orange-400",
    "amber"  => "text-amber-400",
    "green"  => "text-green-400",
    "blue"   => "text-blue-400",
    "purple" => "text-purple-400",
    "red"    => "text-red-400",
    "cyan"   => "text-cyan-400"
  }.freeze

  def avatar_bg_class
    AVATAR_BG_CLASSES[avatar_color] || AVATAR_BG_CLASSES["orange"]
  end

  def avatar_text_class
    AVATAR_TEXT_CLASSES[avatar_color] || AVATAR_TEXT_CLASSES["orange"]
  end
end
