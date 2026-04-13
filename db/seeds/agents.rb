agents = [
  {
    name: "Ripley",
    role: "Team Lead / Orchestrator",
    description: "Coordinates the agent team, delegates tasks, reviews output.",
    llm_model: "ollama/hermes3:8b",
    schedule: "On-demand",
    status: "online",
    avatar_color: "purple",
    position: 1
  },
  {
    name: "Neo 💻",
    role: "Senior Dev",
    description: "Writes features, refactors code, handles complex dev work.",
    llm_model: "claude-opus-4-6",
    schedule: "On-demand",
    status: "online",
    avatar_color: "orange",
    position: 2
  },
  {
    name: "Russ 🔒",
    role: "Security",
    description: "Scans for vulnerabilities, enforces security policies.",
    llm_model: "ollama/hermes3:8b",
    schedule: "Daily 9 AM EDT",
    status: "online",
    avatar_color: "red",
    position: 3
  },
  {
    name: "Vlad ✅",
    role: "Testing",
    description: "Runs tests, catches regressions, validates builds.",
    llm_model: "ollama/hermes3:8b",
    schedule: "Daily 10 AM EDT",
    status: "online",
    avatar_color: "green",
    position: 4
  },
  {
    name: "Knox 🔒",
    role: "DevOps",
    description: "Monitors production, manages deployments, daily health checks.",
    llm_model: "ollama/hermes3:8b",
    schedule: "Daily 8 AM EDT",
    status: "online",
    avatar_color: "cyan",
    position: 5
  },
  {
    name: "Jr 🐣",
    role: "Junior Dev",
    description: "Handles smaller tasks, learns patterns, assists senior agents.",
    llm_model: "claude-haiku-4-5",
    schedule: "On-demand",
    status: "online",
    avatar_color: "amber",
    position: 6
  },
  {
    name: "Scout 🔭",
    role: "Field Agent",
    description: "Explores codebases, gathers intel, scouts new opportunities.",
    llm_model: "ollama/hermes3:8b",
    schedule: "On-demand",
    status: "online",
    avatar_color: "blue",
    position: 7
  }
]

# Rename agents that gained emojis so we update in place instead of duplicating
renames = { "Neo" => "Neo 💻", "Russ" => "Russ 🔒", "Vlad" => "Vlad ✅", "Knox" => "Knox 🔒" }
renames.each do |old_name, new_name|
  Agent.where(name: old_name).update_all(name: new_name)
end

created = 0
updated = 0
agents.each do |attrs|
  agent = Agent.find_or_initialize_by(name: attrs[:name])
  if agent.new_record?
    agent.assign_attributes(attrs)
    created += 1 if agent.save
  else
    agent.update(attrs.except(:status))
    updated += 1
  end
end

puts "Seeded #{created} agents, updated #{updated} (#{agents.size} total)"
