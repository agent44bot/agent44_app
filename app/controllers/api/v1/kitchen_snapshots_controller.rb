module Api
  module V1
    class KitchenSnapshotsController < ApplicationController
      include ApiTokenAuthentication

      skip_before_action :verify_authenticity_token
      allow_unauthenticated_access
      before_action :authenticate_api_token

      # GET /api/v1/kitchen_snapshots/upcoming
      # Returns upcoming events from the latest snapshot that still have seats.
      def upcoming
        snapshot = KitchenSnapshot.order(taken_on: :desc).first
        unless snapshot
          render json: { events: [], message: "No snapshots yet" }
          return
        end

        events = snapshot.kitchen_events
          .upcoming
          .where.not("LOWER(availability) LIKE ? OR LOWER(availability) LIKE ?", "%soldout%", "%closed%")
          .order(:start_at)

        render json: {
          snapshot_id: snapshot.id,
          taken_on: snapshot.taken_on,
          events: events.map { |e|
            {
              name: e.name,
              start_at: e.start_at,
              end_at: e.end_at,
              price: e.price,
              venue: e.venue,
              description: e.description,
              url: e.url,
              availability: e.availability,
              spots_left: e.last_known_spots_left || e.spots_left,
              capacity: e.last_known_capacity || e.capacity
            }
          }
        }
      end

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

        # Capture current spots before overwriting so we can detect changes
        prev_spots = snapshot.persisted? ? snapshot.kitchen_events.pluck(:url, :spots_left).to_h : {}
        # Same-day pre-write availability (Argus scrapes twice a day into one
        # snapshot) — lets the wrongly-closed alert dedupe within the day, not
        # just day-over-day.
        prev_avail = snapshot.persisted? ? snapshot.kitchen_events.pluck(:url, :availability).to_h : {}

        snapshot.kitchen_events.destroy_all if snapshot.persisted?
        snapshot.save!

        created = 0
        events_data.each do |e|
          next unless e[:url].present?

          prev = prev_events[e[:url]]
          # If a class dropped off the calendar and came back, it won't be in the
          # immediately-previous snapshot — find its most recent earlier appearance
          # so carried-forward values (price, spots, high-water) survive the gap.
          prev ||= KitchenEvent.joins(:kitchen_snapshot)
                               .where(url: e[:url])
                               .where(kitchen_snapshots: { taken_on: ...taken_on })
                               .order("kitchen_snapshots.taken_on DESC").first

          # The page hides the price once a class can't be bought (SoldOut or
          # Closed), so the scrape sends it blank. The price hasn't really
          # vanished — carry the last known one forward on any blank, so sold-out
          # classes still contribute real revenue instead of $0.
          price = e[:price].presence || prev&.price

          # "Tickets no longer available" (Closed) ends online sales without
          # selling out — the page then shows 0 left, which would read as a full
          # sellout and inflate tickets_sold to capacity (e.g. 7 sold → 32). A
          # genuine "SoldOut" really is 0 left, so leave it alone. For
          # closed-not-soldout, carry the prior run's spots/capacity forward so
          # tickets_sold stays truthful.
          av = e[:availability].to_s.downcase
          if av.include?("closed") && !av.include?("soldout") && prev
            spots_left = prev.spots_left
            capacity   = prev.capacity
          else
            spots_left = e[:spots_left]
            capacity   = e[:capacity]
          end

          if spots_left.present? && capacity.present?
            last_spots = spots_left.to_i
            last_cap   = capacity.to_i
          else
            # Proxy capacity = high-water mark of spots ever seen for this class.
            # It must only ratchet UP — a drop-off/return or a snapshot gap must
            # never reset it lower, or earlier sales silently fall out of
            # tickets_sold (e.g. seen at 32, returns at 28, baseline must stay 32).
            prior      = prev&.last_known_spots_left || prev&.spots_left
            last_spots = [ spots_left.to_i, prior.to_i ].max
            last_spots = nil unless last_spots.positive?
            last_cap   = prev&.last_known_capacity || prev&.capacity
          end

          snapshot.kitchen_events.create!(
            url:          e[:url],
            name:         e[:name],
            start_at:     e[:start_at],
            end_at:       e[:end_at],
            price:        price,
            availability: e[:availability],
            venue:        e[:venue],
            instructor:   e[:instructor],
            description:  e[:description],
            menu:         e[:menu],
            image_url:    e[:image_url],
            spots_left:   spots_left,
            capacity:     capacity,
            last_known_spots_left: last_spots,
            last_known_capacity:   last_cap,
          )
          created += 1
        end

        notify_ticket_changes(snapshot, prev_spots)
        notify_wrongly_closed(snapshot, prev_events, prev_avail)

        render json: { snapshot_id: snapshot.id, taken_on: taken_on, events_created: created }, status: :created
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      # Safeguard against a fat-fingered sales-end date: a future class whose
      # online sales read "Closed" too far ahead to be a normal cutoff, with
      # seats still unsold (Lora's team keeps catching these by hand). Alert only
      # on classes NEWLY in that state since the prior snapshot — created
      # already-closed, or flipped open → closed — so a stuck one doesn't
      # re-alert every day until someone fixes the date on Tock. "Previous state"
      # is the same-day pre-write availability if we re-scraped today, else
      # yesterday's snapshot — so neither a twice-daily run nor a new day fires a
      # duplicate.
      def notify_wrongly_closed(snapshot, prev_events, prev_avail)
        newly = KitchenSnapshot.wrongly_closed_upcoming(snapshot: snapshot).select do |e|
          was = prev_avail[e.url] || prev_events[e.url]&.availability
          was.nil? || !was.to_s.downcase.include?("closed")
        end
        return if newly.empty?

        if newly.size == 1
          e = newly.first
          title = "Class closed too early: #{e.name}"
          body  = "Sales are off for #{e.start_at.strftime('%a %b %-d')}, but seats remain. Looks like a wrong sales-end date. Check it on Tock."
        else
          title = "#{newly.size} classes closed too early"
          lines = newly.first(5).map { |e| "#{e.name} (#{e.start_at.strftime('%b %-d')})" }
          lines << "+ #{newly.size - 5} more" if newly.size > 5
          body = "Sales are off but seats remain. Looks like wrong sales-end dates. Check them on Tock.\n\n" + lines.join("\n")
        end

        broadcast_kitchen_alert(title: title, body: body, apns_url: "/nykitchen", apns_subtitle: nil, level: "warning")
      end

      def notify_ticket_changes(snapshot, prev_spots)
        return if prev_spots.empty?

        changes = snapshot.kitchen_events.filter_map do |event|
          old_spots = prev_spots[event.url]
          new_spots = event.spots_left
          next unless old_spots && new_spots && new_spots < old_spots
          week_index, week_label = week_info_for(event)
          {
            event:       event,
            old_spots:   old_spots,
            new_spots:   new_spots,
            week_index:  week_index,
            week_label:  week_label
          }
        end

        return if changes.empty?

        # Surface highest-signal items first: sold-outs, then biggest movers.
        sorted = changes.sort_by do |c|
          [ c[:new_spots] == 0 ? 0 : 1, -(c[:old_spots] - c[:new_spots]), c[:week_index] ]
        end

        if sorted.size == 1
          notify_single_change(sorted.first)
        else
          notify_digest(snapshot, sorted)
        end
      end

      def notify_single_change(change)
        event = change[:event]
        old_spots = change[:old_spots]
        new_spots = change[:new_spots]
        tickets_bought = old_spots - new_spots
        sold_out = new_spots == 0

        title = if sold_out
          "#{event.name}: #{tickets_bought} ticket(s) bought — SOLD OUT"
        else
          "#{event.name}: #{tickets_bought} ticket(s) bought — #{new_spots} spot(s) left"
        end

        body = "#{old_spots} → #{new_spots} spots remaining"
        url = "/nykitchen#week-#{change[:week_index]}"
        broadcast_kitchen_alert(title: title, body: body, apns_url: url, apns_subtitle: change[:week_label])
      end

      def notify_digest(snapshot, changes)
        total_tickets = changes.sum { |c| c[:old_spots] - c[:new_spots] }
        sold_out_count = changes.count { |c| c[:new_spots] == 0 }

        digest = snapshot.kitchen_ticket_digests.create!(
          total_tickets:  total_tickets,
          sold_out_count: sold_out_count,
          change_count:   changes.size,
          entries: changes.map { |c| serialize_change(c) }
        )

        title = "#{changes.size} classes: #{total_tickets} ticket(s) bought"
        title += " — #{sold_out_count} sold out" if sold_out_count > 0

        lines = changes.first(5).map do |c|
          name = c[:event].name.to_s
          name = name[0, 35] + "…" if name.length > 36
          if c[:new_spots] == 0
            "#{name}: SOLD OUT (#{c[:old_spots]} → 0)"
          else
            "#{name}: #{c[:old_spots]} → #{c[:new_spots]}"
          end
        end
        lines << "+ #{changes.size - 5} more" if changes.size > 5

        broadcast_kitchen_alert(
          title: title,
          body: lines.join("\n"),
          apns_url: "/nykitchen/digests/#{digest.id}",
          apns_subtitle: nil
        )
      end

      # Sends one Telegram + creates one user-less notification record (for the
      # admin activity log), then sends a per-user APNs push to each kitchen
      # recipient so each recipient's iOS app icon badge tracks their own
      # unread count. Recipients are admins + members of the ny-kitchen
      # workspace (today: Rich + Lora).
      def broadcast_kitchen_alert(title:, body:, apns_url:, apns_subtitle:, level: "info")
        Notification.notify!(
          level: level,
          source: "kitchen_tickets",
          title: title,
          body: body,
          telegram: true,
          apns: false
        )

        kitchen_recipients.each do |user|
          Notification.notify!(
            level: level,
            source: "kitchen_tickets",
            title: title,
            body: body,
            telegram: false,
            apns: true,
            apns_url: apns_url,
            apns_subtitle: apns_subtitle,
            apns_user: user
          )
        end
      end

      def kitchen_recipients
        admin_ids = User.where(role: "admin").pluck(:id)
        member_ids = Workspace.find_by(slug: "nykitchen")&.users&.pluck(:id) || []
        User.where(id: admin_ids + member_ids).where.not(email_address: nil)
      end

      def serialize_change(c)
        e = c[:event]
        {
          url:                 e.url,
          name:                e.name,
          start_at:            e.start_at&.iso8601,
          instructor:          e.instructor,
          price:               e.price,
          image_url:           e.image_url,
          capacity:            e.capacity,
          last_known_capacity: e.last_known_capacity,
          old_spots:           c[:old_spots],
          new_spots:           c[:new_spots],
          tickets_bought:      c[:old_spots] - c[:new_spots],
          sold_out:            c[:new_spots] == 0,
          week_index:          c[:week_index],
          week_label:          c[:week_label]
        }
      end

      # Returns [week_index, label] for an event relative to the current week.
      # Week boundaries match the list view: today → this Sunday, then 7-day spans.
      def week_info_for(event)
        today = Date.today
        event_date = event.start_at.to_date
        days_until_sunday = (7 - today.cwday) % 7
        this_sunday = today + days_until_sunday

        if event_date <= this_sunday
          [ 0, "Current Week" ]
        else
          weeks_ahead = ((event_date - this_sunday - 1).to_i / 7) + 1
          case weeks_ahead
          when 1 then [ 1, "Next Week" ]
          else [ weeks_ahead, "In #{weeks_ahead} Weeks" ]
          end
        end
      end
    end
  end
end
