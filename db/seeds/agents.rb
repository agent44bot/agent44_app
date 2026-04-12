agents = [
  {
    name: "Ripley",
    role: "Team Lead / Orchestrator",
    description: "Coordinates the agent team, delegates tasks, reviews output.",
    llm_model: "ollama/qwen2.5-coder:7b",
    schedule: "On-demand",
    status: "online",
    avatar_color: "purple",
    position: 1
  },
  {
    name: "Neo",
    role: "Developer",
    description: "Writes features, refactors code, handles complex dev work.",
    llm_model: "openrouter/claude-opus-4-6",
    schedule: "On-demand",
    status: "online",
    avatar_color: "orange",
    position: 2
  },
  {
    name: "Russ",
    role: "Security Guardian",
    description: "Scans for vulnerabilities, enforces security policies.",
    llm_model: "ollama/qwen2.5-coder:7b",
    schedule: "Daily 9 AM EDT",
    status: "online",
    avatar_color: "red",
    position: 3
  },
  {
    name: "Vlad",
    role: "Test Validator",
    description: "Runs tests, catches regressions, validates builds.",
    llm_model: "ollama/qwen2.5-coder:7b",
    schedule: "Daily 10 AM EDT",
    status: "online",
    avatar_color: "green",
    position: 4
  },
  {
    name: "Knox",
    role: "DevOps / Production Monitor",
    description: "Monitors production, manages deployments, daily health checks.",
    llm_model: "ollama/qwen2.5-coder:7b",
    schedule: "Daily 8 AM EDT",
    status: "online",
    avatar_color: "cyan",
    position: 5
  }
]

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
