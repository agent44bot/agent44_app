require "json"
require "fileutils"

module FeedbackAgent
  # One pass over the queue per #tick: take the oldest item, claim it, run its
  # step (plan / build / merge), report back. Any failure is reported as
  # "stuck" on the item, and Rich can Retry it from the board.
  class Worker
    PLAN_TOOLS = %w[Read Grep Glob].freeze
    BUILD_TOOLS = [
      "Read", "Edit", "Write", "Grep", "Glob",
      "Bash(bin/rails test:*)", "Bash(bin/rails db:migrate:*)", "Bash(bin/rails generate:*)",
      "Bash(bin/rubocop:*)", "Bash(bin/brakeman:*)",
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git add:*)", "Bash(git commit:*)",
      "Bash(ls:*)", "Bash(cat:*)", "Bash(grep:*)"
    ].freeze
    # Never available to the agent: no network, no pushing or merging, no
    # production access. The worker does those itself, after Rich's gates.
    DENIED_TOOLS = [ "WebFetch", "WebSearch", "Bash(git push:*)", "Bash(gh:*)", "Bash(fly:*)",
                     "Bash(flyctl:*)", "Bash(curl:*)" ].freeze
    REQUIRED_CHECKS = [ "test", "claude / auto-review" ].freeze

    Config = Struct.new(:repo_dir, :work_root, :gh_repo, :prod_url, :fly_app, :claude_bin, :model,
                        :checks_timeout, :deploy_timeout, :poll_interval, keyword_init: true)

    def initialize(api:, shell:, config:, log: ->(msg) { puts("[#{Time.now.strftime('%F %T')}] #{msg}") },
                   sleeper: ->(s) { sleep(s) })
      @api, @sh, @c, @log, @sleep = api, shell, config, log, sleeper
    end

    # Returns :idle, :busy (claimed by someone else), or the step it ran.
    def tick
      item = @api.queue.first
      return :idle unless item

      begin
        @api.claim(item["id"])
      rescue Api::Conflict
        return :busy
      end

      step = item["step"]
      @log.call("feedback ##{item['id']}: #{step}")
      send(step, item)
      step.to_sym
    rescue StandardError => e
      raise unless item # the queue itself failed: let the loop log and retry
      @log.call("feedback ##{item['id']}: stuck: #{e.message}")
      begin
        @api.error(item["id"], message: "#{step} failed: #{e.message}")
      rescue StandardError => report_error
        @log.call("could not report the error: #{report_error.message}")
      end
      :error
    end

    # ---- plan: read-only Claude Code writes the plan ----

    def plan(item)
      dir = worktree("plan-#{item['id']}") { |path| git("worktree", "add", "--detach", path, "origin/main") }
      files = attachments(item)
      out = claude(Prompts.plan(item, files), chdir: dir, tools: PLAN_TOOLS, mode: "default",
                   schema: Prompts::PLAN_SCHEMA, add_dirs: [ attachments_dir(item) ])
      @api.plan(item["id"], plan: out.fetch("plan"), question: out["question"])
    ensure
      remove_worktree(dir) if dir
    end

    # ---- build: Claude Code commits on feedback/<id>; the worker pushes ----

    def build(item)
      id = item["id"]
      branch = "feedback/#{id}"
      number = item.dig("pr", "number")
      base = number && remote_branch?(branch) ? "origin/#{branch}" : "origin/main"
      dir = worktree("build-#{id}") { |path| git("worktree", "add", "-B", branch, path, base) }
      failing = number ? failing_checks(number).join(", ").then { |s| s.empty? ? nil : s } : nil
      before = rev(dir)

      out = claude(Prompts.build(item, attachments(item), failing_checks: failing), chdir: dir,
                   tools: BUILD_TOOLS, mode: "acceptEdits", schema: Prompts::BUILD_SCHEMA,
                   add_dirs: [ attachments_dir(item) ])
      commit_leftovers(dir, id, out["title"])
      head = rev(dir)
      raise "the agent made no changes" if head == before

      @sh.run("git", "push", "-u", "origin", branch, chdir: dir)
      number, url = number ? [ number, item.dig("pr", "url") ] : open_pr(item, branch, out)
      report = { number: number, url: url, head_sha: head, summary: out["summary"], ship_note: out["ship_note"] }
      @api.pr(id, **report, checks: "pending")

      result, failed = wait_for_checks(number, head)
      raise "checks failed on PR ##{number}: #{failed.join(', ')}" unless result == "green"
      @api.pr(id, **report, checks: "green")
    ensure
      remove_worktree(dir) if dir
    end

    # ---- merge: only after Rich's Merge it, only the SHA he approved ----

    def merge(item)
      id, number, sha = item["id"], item.dig("pr", "number"), item["merge_requested_sha"]
      raise "no PR or approved SHA to merge" unless number && sha

      pr = gh_json("pr", "view", number.to_s, "--json", "headRefOid,state")
      raise "PR ##{number} is #{pr['state']}, not open" unless pr["state"] == "OPEN"
      raise "PR ##{number} moved to #{pr['headRefOid'][0, 7]} after Rich approved #{sha[0, 7]}" unless pr["headRefOid"] == sha
      failed = failing_checks(number)
      raise "checks not green on PR ##{number}: #{failed.join(', ')}" if failed.any?

      @sh.run("gh", "pr", "merge", number.to_s, "--repo", @c.gh_repo, "--squash", "--delete-branch",
              "--match-head-commit", sha, chdir: @c.work_root)
      merged = gh_json("pr", "view", number.to_s, "--json", "mergeCommit,state")
      raise "PR ##{number} did not merge (#{merged['state']})" unless merged["state"] == "MERGED"
      wait_for_deploy(merged.dig("mergeCommit", "oid"))
      verify_prod
      @api.shipped(id, sha: sha)
      @sh.run("git", "-C", @c.repo_dir, "branch", "-D", "feedback/#{id}", allow_failure: true)
    end

    private

    def claude(prompt, chdir:, tools:, mode:, schema:, add_dirs: [])
      cmd = [ @c.claude_bin, "-p", prompt, "--output-format", "json", "--json-schema", JSON.generate(schema),
              "--permission-mode", mode ]
      cmd += [ "--model", @c.model ] if @c.model
      add_dirs.each { |d| cmd += [ "--add-dir", d ] }
      cmd += [ "--allowedTools", *tools, "--disallowedTools", *DENIED_TOOLS ]
      # Use this machine's Claude Code login, not the API key the smoke env
      # exports (that would bill the app's API key).
      raw = @sh.run(*cmd, chdir: chdir, env: { "ANTHROPIC_API_KEY" => nil })
      res = JSON.parse(raw)
      raise "claude: #{res['result'].to_s[0, 500]}" if res["is_error"]
      @log.call("claude #{mode}: $#{res['total_cost_usd']&.round(2)}, #{res['num_turns']} turns")
      res["structured_output"] || raise("claude returned no structured output")
    end

    def attachments_dir(item) = File.join(@c.work_root, "attachments", item["id"].to_s)

    def attachments(item)
      dir = attachments_dir(item)
      FileUtils.mkdir_p(dir)
      Array(item["attachments"]).each_with_index.map do |a, i|
        path = File.join(dir, "#{i + 1}-#{File.basename(a['filename'])}")
        @api.download(a["url"], path) unless File.exist?(path)
        path
      end
    end

    def git(*args) = @sh.run("git", "-C", @c.repo_dir, *args)

    # A fresh worktree under work_root; never touches the shared checkout.
    def worktree(name)
      git("fetch", "--quiet", "origin")
      path = File.join(@c.work_root, "worktrees", name)
      remove_worktree(path) if File.exist?(path)
      FileUtils.mkdir_p(File.dirname(path))
      yield path
      path
    end

    def remove_worktree(path)
      @sh.run("git", "-C", @c.repo_dir, "worktree", "remove", "--force", path, allow_failure: true)
      FileUtils.rm_rf(path)
    end

    def rev(dir) = @sh.run("git", "rev-parse", "HEAD", chdir: dir).strip

    def remote_branch?(branch)
      _out, ok = @sh.run("git", "-C", @c.repo_dir, "rev-parse", "--verify", "--quiet", "origin/#{branch}",
                         allow_failure: true)
      ok
    end

    # Anything the agent edited but didn't commit still ships in this PR.
    def commit_leftovers(dir, id, title)
      return if @sh.run("git", "status", "--porcelain", chdir: dir).strip.empty?
      @sh.run("git", "add", "-A", chdir: dir)
      @sh.run("git", "commit", "-m", "Feedback ##{id}: #{title}\n\nCo-Authored-By: Claude <noreply@anthropic.com>", chdir: dir)
    end

    def open_pr(item, branch, out)
      body = <<~MD
        From feedback ##{item['id']} (#{item['sender']}): "#{item['message'].to_s.gsub(/\s+/, ' ')[0, 300]}"

        #{out['summary']}

        Approved plan:
        #{item['plan']}

        Board: #{item['admin_url']}

        🤖 Generated with [Claude Code](https://claude.com/claude-code)
      MD
      url = @sh.run("gh", "pr", "create", "--repo", @c.gh_repo, "--head", branch, "--base", "main",
                    "--title", out["title"], "--body", body, chdir: @c.work_root).strip.lines.last.strip
      [ url[%r{/pull/(\d+)}, 1].to_i, url ]
    end

    def gh_json(*args)
      JSON.parse(@sh.run("gh", *args, "--repo", @c.gh_repo, chdir: @c.work_root))
    end

    def checks(number)
      out, _ok = @sh.run("gh", "pr", "checks", number.to_s, "--repo", @c.gh_repo, "--json", "name,bucket",
                         chdir: @c.work_root, allow_failure: true) # exits non-zero while pending or failing
      JSON.parse(out.to_s.strip.empty? ? "[]" : out)
    end

    def failing_checks(number)
      checks(number).select { |c| %w[fail cancel].include?(c["bucket"]) }.map { |c| c["name"] }
    end

    # Waits until the PR's head is `sha` and the required checks have settled.
    def wait_for_checks(number, sha)
      deadline = Time.now + @c.checks_timeout
      loop do
        raise "checks still running on PR ##{number} after #{@c.checks_timeout / 60} min" if Time.now > deadline
        @sleep.call(@c.poll_interval)
        next unless gh_json("pr", "view", number.to_s, "--json", "headRefOid")["headRefOid"] == sha

        list = checks(number)
        names = list.map { |c| c["name"] }
        next unless REQUIRED_CHECKS.all? { |r| names.include?(r) }
        next if list.any? { |c| c["bucket"] == "pending" }

        failed = list.select { |c| %w[fail cancel].include?(c["bucket"]) }.map { |c| c["name"] }
        return [ failed.empty? ? "green" : "red", failed ]
      end
    end

    def wait_for_deploy(merge_sha)
      deadline = Time.now + @c.deploy_timeout
      loop do
        raise "no finished deploy for #{merge_sha[0, 7]} after #{@c.deploy_timeout / 60} min" if Time.now > deadline
        @sleep.call(@c.poll_interval)
        runs = JSON.parse(@sh.run("gh", "run", "list", "--repo", @c.gh_repo, "--workflow", "fly-deploy.yml",
                                  "--limit", "10", "--json", "headSha,status,conclusion", chdir: @c.work_root))
        run = runs.find { |r| r["headSha"] == merge_sha }
        next unless run && run["status"] == "completed"
        raise "deploy of #{merge_sha[0, 7]} finished #{run['conclusion']}" unless run["conclusion"] == "success"
        return
      end
    end

    # The runbook's two checks: the site answers 200, and SolidQueue has live
    # processes (a crash loop can serve a lucky 200 with the jobs dead).
    def verify_prod
      code = @sh.run("curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", @c.prod_url).strip
      raise "prod returned #{code} after the deploy" unless code == "200"
      out = @sh.run("fly", "ssh", "console", "-a", @c.fly_app, "-C",
                    "bin/rails runner 'puts SolidQueue::Process.count'", chdir: @c.work_root)
      count = out.lines.map(&:strip).grep(/\A\d+\z/).last.to_i
      raise "prod has no SolidQueue processes after the deploy" unless count.positive?
    end
  end
end
