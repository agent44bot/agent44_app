module Admin
  class ChatController < BaseController
    def index
      @messages = AgentMessage.recent.last(50)
      @agents = Agent.ordered
    end

    def create
      agent = params[:agent].presence || "ripley"
      content = params[:content]&.strip
      return redirect_to admin_chat_path if content.blank?

      AgentMessage.create!(role: "user", agent: agent, content: content, status: "pending")
      redirect_to admin_chat_path
    end

    # GET /admin/chat/messages.json — polled by the chat UI for live updates
    def messages
      since = params[:since].present? ? Time.zone.parse(params[:since]) : 1.hour.ago
      messages = AgentMessage.where("created_at > ?", since).recent
      render json: messages.map { |m|
        { id: m.id, role: m.role, agent: m.agent, content: m.content, status: m.status,
          created_at: m.created_at.iso8601 }
      }
    end
  end
end
