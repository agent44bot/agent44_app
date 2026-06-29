# Publishes a single WorkspaceDraft: dispatches its body to each requested
# platform via WorkspacePosts::Dispatcher, then updates the draft's status
# (published / partial / failed) and stores the per-platform result lines.
module WorkspaceDrafts
  class Publisher
    def initialize(draft)
      @draft = draft
    end

    def call
      result = WorkspacePosts::Dispatcher.new(
        @draft.workspace,
        author:     @draft.author,
        body:       @draft.body,
        platforms:  @draft.target_platforms,
        image:      @draft.image,
        image_url:  @draft.image_url,
        source_url: @draft.source_url
      ).dispatch

      @draft.update!(
        status:       summarize_status(result),
        results:      result.successes + result.failures,
        error:        result.failures.join(" · ").presence,
        published_at: Time.current
      )
      result
    end

    private

    def summarize_status(result)
      return "published" if result.all_ok?
      return "failed"    if result.all_bad?
      "partial"
    end
  end
end
