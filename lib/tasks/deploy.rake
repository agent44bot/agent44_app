desc "Show the deploy playbook"
task :deploy do
  puts <<~PLAYBOOK

    ╔════════════════════════════════════════════════════════════════════╗
    ║                    agent44_app deploy playbook                    ║
    ╚════════════════════════════════════════════════════════════════════╝

      rake deploy:live      → git pull && fly deploy + Knox status narration ($0)
      rake openclaw:deploy  → route through Knox via OpenClaw (Haiku tokens)

  PLAYBOOK
end

namespace :deploy do
  desc "Deploy with live Knox status narration on agent44labs.com ($0)"
  task :live do
    knox_status "busy", "Pulling latest from origin..."
    sh "git pull --ff-only"

    knox_status "busy", "Running fly deploy — building image..."
    IO.popen("fly deploy 2>&1") do |io|
      io.each_line do |line|
        puts line
        case line
        when /pushing manifest|Pushing image/i
          knox_status "busy", "Pushing image to registry..."
        when /Updating machine/i
          knox_status "busy", "Updating production machine..."
        when /Waiting for machine/i
          knox_status "busy", "Waiting for machine to start..."
        when /reached started state/i
          knox_status "busy", "Machine started, running health checks..."
        when /reached good state|is now in a good state/i
          knox_status "busy", "Health checks passed, finalizing..."
        end
      end
    end

    if $?.success?
      knox_status "online", ""
      puts "✓ Deploy complete"
    else
      knox_status "error", "fly deploy failed (exit #{$?.exitstatus})"
      abort "✗ Deploy failed"
    end
  end

end

def knox_status(status, task = "")
  script = File.expand_path("~/.openclaw/skills/update-agent-status.sh")
  system("bash", script, "Knox 🔒", status, task) if File.exist?(script)
end
