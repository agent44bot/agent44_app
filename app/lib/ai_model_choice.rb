# Per-feature Anthropic model selection for the NY Kitchen workspace. Owners /
# admins pick a model per feature on the billing page (radios in the AI usage
# table); the choice is stored in Setting (kv) and each AI call site resolves
# its model through here, falling back to the feature's code default when unset.
module AiModelChoice
  # Selectable models: key -> { id, label, blurb } for the billing legend.
  OPTIONS = {
    "opus"   => { id: "claude-opus-4-8",            label: "Opus",   blurb: "highest quality ($5/$25 per M tokens)" },
    "sonnet" => { id: "claude-sonnet-4-6",          label: "Sonnet", blurb: "balanced ($3/$15 per M tokens)" },
    "haiku"  => { id: "claude-haiku-4-5-20251001",  label: "Haiku",  blurb: "fastest & cheapest ($1/$5 per M tokens)" }
  }.freeze

  KEYS = OPTIONS.keys.freeze

  # Each billable feature's source -> the model key the code uses by default
  # (what runs when no override is saved).
  DEFAULTS = {
    "nyk_grocery_list"    => "opus",
    "nyk_recipe_extract"  => "opus",
    "nyk_receipt_extract" => "opus",
    "nyk_ask"             => "haiku",
    "nyk_team_report"     => "haiku",
    "nyk_enhance"         => "haiku",
    "nyk_x_autopost"      => "haiku"
  }.freeze

  # Sources whose model is resolved from an in-app call site we control, so the
  # billing UI shows radios for them. Others (e.g. the X autopost draft, which
  # an external job generates) are shown read-only.
  CONTROLLABLE = %w[nyk_grocery_list nyk_recipe_extract nyk_receipt_extract nyk_ask nyk_team_report nyk_enhance].freeze

  def self.setting_key(source)
    "ai_model:#{source}"
  end

  # The model id a feature should use: the saved override, else `default` (the
  # call site's own MODEL constant).
  def self.resolve(source, default:)
    OPTIONS.dig(Setting.get(setting_key(source)), :id) || default
  end

  # The selected model key for the UI: the saved override, else the feature's
  # documented default, else haiku.
  def self.selected_key(source)
    saved = Setting.get(setting_key(source))
    return saved if KEYS.include?(saved)
    DEFAULTS[source] || "haiku"
  end

  # Save an override. Raises on an unknown model key.
  def self.set(source, key)
    raise ArgumentError, "unknown model #{key.inspect}" unless KEYS.include?(key)
    Setting.set(setting_key(source), key)
  end

  def self.controllable?(source)
    CONTROLLABLE.include?(source)
  end
end
