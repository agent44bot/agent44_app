module Api
  module V1
    class AgentsController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token, only: :update_status

      # GET /api/v1/agents/statuses (no cache — always fresh for live polling)
      def statuses
        agents = Agent.ordered
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

      # Window long enough to cover a typical deploy: Knox flips his own
      # status multiple times per turn (pre-pull, pre-deploy, post-deploy)
      # and each pair of transitions can be 60+ seconds apart. 300s catches
      # all duplicates inside a single deploy without silencing unrelated
      # later activity.
      NOTIFY_DEBOUNCE_SECONDS = 60

      def notify_status_change(agent, old_status)
        case agent.status
        when "busy"
          task = agent.current_task.presence || "a task"
          notify_once_per_window(agent, "busy",
            level: "info",
            title: "#{agent.name} is now working",
            body: task
          )
        when "error"
          task = agent.current_task.presence || "Unknown error"
          # Always notify on error — losing one of these is worse than a dupe.
          Notification.notify!(
            level: "error",
            source: "agent_status",
            title: "#{agent.name} encountered an error",
            body: task,
            telegram: true
          )
        when "online"
          if old_status == "busy"
            notify_once_per_window(agent, "finished",
              level: "success",
              title: "#{agent.name} finished task"
            )
          end
        end
      end

      # Debounce repeat notifications for the same agent + transition
      # (OpenClaw flips an agent's status multiple times per turn, producing
      # 3x duplicate Telegram pings). Key: agent_id + transition kind.
      def notify_once_per_window(agent, kind, level:, title:, body: nil)
        cache_key = "agent_status/#{agent.id}/#{kind}"
        return if Rails.cache.read(cache_key)

        Notification.notify!(
          level: level,
          source: "agent_status",
          title: title,
          body: body,
          telegram: true
        )
        Rails.cache.write(cache_key, true, expires_in: NOTIFY_DEBOUNCE_SECONDS)
      end
    end
  end
end
