module Api
  module V1
    class ChatController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token

      # GET /api/v1/chat/pending — Mac Mini poller fetches pending messages
      def pending
        messages = AgentMessage.pending.order(:created_at)
        render json: messages.map { |m|
          { id: m.id, agent: m.agent, content: m.content, created_at: m.created_at.iso8601 }
        }
      end

      # PATCH /api/v1/chat/:id/ack — Mark message as sent (poller picked it up)
      def ack
        message = AgentMessage.find(params[:id])
        message.update!(status: "sent")
        render json: { id: message.id, status: "sent" }
      end

      # POST /api/v1/chat/reply — Agent posts a response
      def reply
        AgentMessage.find(params[:id]).update!(status: "delivered") if params[:id].present?
        message = AgentMessage.create!(
          role: "assistant",
          agent: params[:agent] || "ripley",
          content: params[:content],
          status: "delivered"
        )
        render json: { id: message.id, status: "delivered" }
      end
    end
  end
end
