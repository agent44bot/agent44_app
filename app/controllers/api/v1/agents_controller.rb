module Api
  module V1
    class AgentsController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token, only: :update_status

      # GET /api/v1/agents/statuses
      def statuses
        agents = Rails.cache.fetch("agents/ordered", expires_in: 30.seconds) { Agent.ordered.to_a }
        render json: agents.map { |a|
          { name: a.name, status: a.status, task: a.status_label, role: a.role }
        }
      end

      # PATCH /api/v1/agents/:name/status
      # Body: { status: "busy", current_task: "Security scanning FitCorn" }
      def update_status
        agent = Agent.find_by!(name: params[:name])
        old_status = agent.status
        agent.update!(
          status: params[:status],
          current_task: params[:current_task],
          last_active_at: Time.current
        )
        Rails.cache.delete("agents/ordered")
        notify_status_change(agent, old_status) if old_status != agent.status
        render json: { agent: agent.name, status: agent.status, current_task: agent.current_task }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Agent not found" }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def notify_status_change(agent, old_status)
        case agent.status
        when "busy"
          task = agent.current_task.presence || "a task"
          Notification.notify!(
            level: "info",
            source: "agent_status",
            title: "#{agent.name} is now working",
            body: task,
            telegram: true
          )
        when "error"
          task = agent.current_task.presence || "Unknown error"
          Notification.notify!(
            level: "error",
            source: "agent_status",
            title: "#{agent.name} encountered an error",
            body: task,
            telegram: true
          )
        when "online"
          if old_status == "busy"
            Notification.notify!(
              level: "success",
              source: "agent_status",
              title: "#{agent.name} finished task",
              telegram: true
            )
          end
        end
      end
    end
  end
end
