module Api
  module V1
    class AgentsController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access

      before_action :authenticate_api_token, only: %i[update_status update_profile add_memory]

      # GET /api/v1/agents/statuses (no cache — always fresh for live polling)
      def statuses
        agents = Agent.ordered
        render json: agents.map { |a|
          { name: a.name, status: a.effective_status, task: a.status_label, role: a.role }
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

      # PUT /api/v1/agents/:slug/profile
      # Body: { identity_markdown: "...", soul_markdown: "...", skills: ["..."] }
      # Pushed from the Mac Mini sync job (IDENTITY.md + SOUL.md).
      def update_profile
        agent = Agent.find_by!(slug: params[:slug])
        agent.update!(
          identity_markdown: params[:identity_markdown],
          soul_markdown: params[:soul_markdown],
          skills: params[:skills].nil? ? agent.skills : Array(params[:skills])
        )
        render json: { agent: agent.slug, ok: true }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Agent not found" }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/agents/:slug/memories
      # Body: { memories: [ { filename:, title:, body:, occurred_at:, source: }, ... ] }
      # Upserts by filename so re-syncing the mini's memory/*.md is idempotent.
      def add_memory
        agent = Agent.find_by!(slug: params[:slug])
        entries = params.permit(memories: %i[filename title body occurred_at source])[:memories]
        synced = 0
        Array(entries).each do |entry|
          next if entry[:body].blank?
          key = entry[:filename].presence || entry[:title].presence
          memory = agent.agent_memories.find_or_initialize_by(filename: key)
          memory.assign_attributes(
            title: entry[:title],
            body: entry[:body],
            occurred_at: entry[:occurred_at],
            source: entry[:source]
          )
          memory.save!
          synced += 1
        end
        render json: { agent: agent.slug, synced: synced }
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
