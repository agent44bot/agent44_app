class Agent < ApplicationRecord
  STATUSES = %w[online busy error offline].freeze
  COLORS = %w[orange amber green blue purple red cyan].freeze

  validates :name, presence: true, uniqueness: true
  validates :role, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :avatar_color, inclusion: { in: COLORS }

  scope :ordered, -> { order(:position, :name) }
  scope :active, -> { where.not(status: "offline") }

  def online?  = status == "online"
  def busy?    = status == "busy"
  def error?   = status == "error"
  def offline? = status == "offline"

  def initials
    name[0].upcase
  end

  def status_color
    case status
    when "online" then "green"
    when "busy"   then "amber"
    when "error"  then "red"
    else "gray"
    end
  end

  def status_label
    case status
    when "busy"  then current_task.presence || "Working on a task"
    when "error" then current_task.presence || "Task failed"
    else status.capitalize
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
