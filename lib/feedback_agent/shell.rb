require "open3"

module FeedbackAgent
  # Runs commands (git, gh, claude, fly, curl). A separate object so the
  # worker's tests can swap in a scripted fake.
  class Shell
    class Failed < StandardError; end

    # Returns stdout. On a non-zero exit, raises Failed with the tail of
    # stderr (or stdout), unless allow_failure, which returns [stdout, ok?].
    def run(*cmd, chdir: nil, env: {}, allow_failure: false, stdin: nil)
      opts = {}
      opts[:chdir] = chdir if chdir
      opts[:stdin_data] = stdin if stdin
      out, err, status = Open3.capture3(env, *cmd, **opts)
      return [ out, status.success? ] if allow_failure
      return out if status.success?

      detail = (err.strip.empty? ? out : err).strip
      raise Failed, "#{cmd.first(3).join(' ')} exited #{status.exitstatus}: #{detail[-1500..] || detail}"
    end
  end
end
