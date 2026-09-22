# Started by bin/feedback-agent (not directly). Kept out of lib/ so Rails
# never eager-loads a file that runs a loop.
# Feedback text and Claude's output are UTF-8 whatever the locale says.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
require_relative "../lib/feedback_agent"
%w[api shell prompts worker].each { |f| require_relative "../lib/feedback_agent/#{f}" }

root = File.expand_path("..", __dir__)
work_root = ENV.fetch("FEEDBACK_AGENT_HOME", File.join(Dir.home, ".feedback-agent"))
FileUtils.mkdir_p(work_root)

# One worker per machine: a second copy exits instead of double-building.
lock = File.open(File.join(work_root, "agent.lock"), File::RDWR | File::CREAT)
abort "feedback-agent is already running" unless lock.flock(File::LOCK_EX | File::LOCK_NB)

config = FeedbackAgent::Worker::Config.new(
  repo_dir: ENV.fetch("FEEDBACK_AGENT_REPO", root),
  work_root: work_root,
  gh_repo: "agent44bot/agent44_app",
  prod_url: ENV.fetch("FEEDBACK_API_BASE", "https://agent44labs.com"),
  fly_app: "agent44-app",
  claude_bin: ENV.fetch("CLAUDE_BIN", "claude"),
  model: ENV.fetch("FEEDBACK_AGENT_MODEL", "claude-opus-5-5"),
  checks_timeout: 30 * 60,
  deploy_timeout: 25 * 60,
  poll_interval: 20
)
api = FeedbackAgent::Api.new(base_url: config.prod_url, token: ENV.fetch("API_TOKEN"))
worker = FeedbackAgent::Worker.new(api: api, shell: FeedbackAgent::Shell.new, config: config)
$stdout.sync = true
puts "[#{Time.now.strftime('%F %T')}] feedback-agent up (#{config.prod_url}, model #{config.model})"

loop do
  begin
    result = worker.tick
  rescue StandardError => e
    puts "[#{Time.now.strftime('%F %T')}] queue error: #{e.message}"
    result = :idle
  end
  break if ARGV.include?("--once")
  sleep(result == :idle ? 60 : 5) # straight on to the next item after real work
end
