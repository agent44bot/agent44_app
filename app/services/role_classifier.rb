# Classifies a job posting into one of three buckets:
#   - "traditional"    : test/QA/dev work with no AI angle
#   - "ai_augmented"   : knows or uses AI/ML tools as part of the job
#   - "agent_director" : the role we sketched on /lab — humans who direct
#                        teams of AI agents to build/test/ship software
#
# agent_director takes precedence over ai_augmented when both match.
class RoleClassifier
  # Strong title signals — if any of these appear in the title, it's a director.
  DIRECTOR_TITLE_PATTERNS = [
    /\bagent(ic)?\s+(engineer|developer|architect|lead)/i,
    /\bai\s+agent\b/i,                              # "AI Agent Engineer", "AI Agent Platform"
    /\bagent\s+(platform|systems?)\b/i,             # "Agent Platform", "Agent Systems"
    /\bai\s+(orchestrat\w+|director|conductor)/i,
    /\b(orchestrat\w+)\s+(engineer|lead)/i,
    /\bforward[-\s]deployed\s+(ai|engineer)/i,
    /\bapplied\s+ai\s+(engineer|lead)/i,
    /\bllm\s+(engineer|ops|orchestrat\w+)/i,
    /\bai\s+(engineer|sdet|qa\s+lead|automation\s+lead)/i,
    /\bhead\s+of\s+(ai|agent|llm)/i,
    /\bhuman[-\s]in[-\s]the[-\s]loop\b/i
  ].freeze

  # Body keywords — at least two distinct hits required to flag as director
  # purely from the description, since these terms also appear in plain
  # ML or AI-tool jobs that don't actually involve directing agent teams.
  DIRECTOR_BODY_KEYWORDS = [
    "claude code", "agent orchestration", "multi-agent", "multi agent",
    "agentic workflow", "agentic workflows", "agentic system",
    "llm agents", "agent team", "agent teams",
    "directing agents", "human-in-the-loop", "human in the loop",
    "anthropic claude", "agent sdk", "tool use", "agent runtime"
  ].freeze

  # Broad AI signal — same as the prior Scrapers::Base#ai_augmented? regex.
  AI_PATTERN = /\b(ai|machine learning|ml |llm|artificial intelligence|generative)\b/i

  # Titles that look like a QA/test job — even if the description namedrops
  # AI tools, these are NOT director roles. Director is a job *about* directing
  # agent teams, not a QA job that happens to test an AI system.
  DISQUALIFYING_TITLE_PATTERNS = [
    /\b(qa|quality\s+assurance|test|sdet|automation)\b/i
  ].freeze

  def self.classify(title:, tags: [], description: nil)
    title_s = title.to_s
    tag_s = Array(tags).flatten.map(&:to_s).join(" ")
    desc_s = description.to_s

    title_says_director = DIRECTOR_TITLE_PATTERNS.any? { |re| title_s.match?(re) }
    title_says_qa       = DISQUALIFYING_TITLE_PATTERNS.any? { |re| title_s.match?(re) }

    # Strong title signal wins outright (an "AI Engineer" title beats a stray
    # "test" mention) — but a QA/test title can never be promoted via body
    # keywords alone.
    return "agent_director" if title_says_director

    if desc_s.present? && !title_says_qa
      hay = desc_s.downcase
      hits = DIRECTOR_BODY_KEYWORDS.count { |kw| hay.include?(kw) }
      return "agent_director" if hits >= 2
    end

    combined = "#{title_s} #{tag_s} #{desc_s}".downcase
    return "ai_augmented" if combined.match?(AI_PATTERN)

    "traditional"
  end

  # Convenience: returns true if classified as either ai_augmented or director.
  # Used to keep the legacy boolean column in sync.
  def self.ai_flavored?(role_class)
    role_class == "ai_augmented" || role_class == "agent_director"
  end
end
