module Api
  module V1
    class KitchenSnapshotsController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access
      before_action :authenticate_api_token

      # POST /api/v1/kitchen_snapshots
      # Body: {
      #   taken_on: "2026-04-17",   # optional, defaults to today
      #   events: [
      #     { url: "...", name: "...", start_at: "...", end_at: "...",
      #       price: "...", availability: "...", venue: "...",
      #       instructor: "...", description: "...",
      #       spots_left: 5, capacity: 24 },
      #     ...
      #   ]
      # }
      def create
        taken_on = Date.parse(params[:taken_on] || Date.today.to_s)
        events_data = Array(params[:events])

        previous = KitchenSnapshot.latest_before(taken_on)
        prev_events = previous ? previous.kitchen_events.index_by(&:url) : {}

        snapshot = KitchenSnapshot.find_or_initialize_by(taken_on: taken_on)
        snapshot.kitchen_events.destroy_all if snapshot.persisted?
        snapshot.save!

        created = 0
        events_data.each do |e|
          next unless e[:url].present?

          prev = prev_events[e[:url]]
          if e[:spots_left].present? && e[:capacity].present?
            last_spots = e[:spots_left].to_i
            last_cap   = e[:capacity].to_i
          elsif prev
            last_spots = prev.last_known_spots_left || prev.spots_left
            last_cap   = prev.last_known_capacity || prev.capacity
          end

          snapshot.kitchen_events.create!(
            url:          e[:url],
            name:         e[:name],
            start_at:     e[:start_at],
            end_at:       e[:end_at],
            price:        e[:price],
            availability: e[:availability],
            venue:        e[:venue],
            instructor:   e[:instructor],
            description:  e[:description],
            spots_left:   e[:spots_left],
            capacity:     e[:capacity],
            last_known_spots_left: last_spots,
            last_known_capacity:   last_cap,
          )
          created += 1
        end

        render json: { snapshot_id: snapshot.id, taken_on: taken_on, events_created: created }, status: :created
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
