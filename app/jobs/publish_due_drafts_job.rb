class PublishDueDraftsJob < ApplicationJob
  queue_as :default

  def perform
    WorkspaceDraft.due_now.find_each do |draft|
      WorkspaceDrafts::Publisher.new(draft).call
    rescue => e
      Rails.logger.error("PublishDueDraftsJob: failed publishing WorkspaceDraft ##{draft.id}: #{e.class}: #{e.message}")
      draft.update(status: "failed", error: "#{e.class}: #{e.message}", published_at: Time.current)
    end
  end
end
