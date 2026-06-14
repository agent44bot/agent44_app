module Finance
  # Maps a raw transaction (vendor name + description) to a clean vendor label,
  # a Schedule C friendly category, and a business purpose. Encodes the labeling
  # rules agreed for Agent44 Labs. Unknown vendors fall through to "Uncategorized"
  # and are flagged for review; a small set of known-personal vendors is excluded
  # by default. Everything is editable on the page afterward.
  module ExpenseCategorizer
    module_function

    # Each rule: [matcher_regex, vendor, category, business_purpose, excluded, review_flag]
    RULES = [
      [ /anthropic|claude/i, "Anthropic (Claude)", "Software/Subscriptions", "Claude Max and API; the agent fleet runs on the Claude API", false, nil ],
      [ /openrouter|open router/i, "OpenRouter", "Software/Subscriptions (COGS)", "LLM API access for agents", false, nil ],
      [ /maple/i, "Maple AI", "Software/Subscriptions", "Encrypted AI assistant used for the business", false, nil ],
      [ /lovable/i, "Lovable", "Software/Subscriptions", "AI app builder used for prototyping", false, nil ],
      [ /dnsimple/i, "DNSimple", "Domains/Web", "Domain registration and DNS for business sites", false, nil ],
      [ /fly\.?io/i, "Fly.io", "Hosting", "Production hosting for agent44_app (web and background jobs)", false, nil ],
      [ /mac ?mini/i, "Apple - Mac mini", "Equipment", "Self-hosted CI runner (mac-mini-agent44) for automated NYK smoke tests; also dev machine", false, "Section 179 / de minimis - confirm w/ CPA" ],
      [ /kvm|hdmi|thunderbolt|display adapter|display plug|dummy.*display|cable/i, "Hardware accessory", "Equipment", "Accessory for the headless Mac mini CI runner setup", false, nil ],
      [ /\bx (developer|dev|credit)|x dev console|x api/i, "X API", "Software/Subscriptions", "X (Twitter) API for the Fleet Social auto-posting feature", false, nil ],
      [ /google ?one|google play|google/i, "Google One", "Software/Subscriptions", "Cloud storage for business files and backups", false, nil ],
      [ /best buy/i, "Best Buy", "Equipment", "Hardware purchase", false, "REVIEW - confirm item" ],
      [ /syr univ|syracuse|conference|conf\b/i, "Conference", "Education/Conferences", "AI conference registration; professional education and networking", false, nil ],
      [ /cash app|violet/i, "Contractor", "Contract labor", "Contractor payment for project work", false, nil ],
      # Known-personal: excluded by default, still recorded so the books match the card.
      [ /youtube/i, "YouTube Premium", "Software/Subscriptions", "Typically personal; excluded from business expenses", true, "Excluded (personal)" ],
      [ /nordvpn|nord vpn/i, "NordVPN", "Software/Subscriptions", "Confirm business use", true, "Excluded - confirm business use" ]
    ].freeze

    DEFAULT = { vendor: nil, category: "Uncategorized", business_purpose: nil, excluded: false, review_flag: "Needs review" }.freeze

    # text is the combined vendor/description string from the source row.
    # raw_vendor is the best available vendor label to fall back on.
    def categorize(text, raw_vendor = nil)
      RULES.each do |regex, vendor, category, purpose, excluded, flag|
        next unless text.to_s.match?(regex)
        return { vendor: vendor, category: category, business_purpose: purpose, excluded: excluded, review_flag: flag }
      end
      DEFAULT.merge(vendor: raw_vendor.presence || "Unknown")
    end
  end
end
