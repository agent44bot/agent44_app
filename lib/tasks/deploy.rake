desc "Show the deploy playbook (bin/deploy)"
task :deploy do
  exec "bin/deploy"
end

namespace :deploy do
  desc "Direct deploy: git pull --ff-only && fly deploy ($0, silent)"
  task :ship do
    exec "bin/deploy ship"
  end

  desc "Direct deploy with live status narration on agent44labs.com homepage ($0)"
  task :live do
    exec "bin/deploy ship-live"
  end

  desc "Route deploy through the Knox OpenClaw agent (costs Haiku tokens)"
  task :knox do
    exec "bin/deploy with-knox"
  end
end
