# Sam's twice-a-day class promo drafts. Each eligible run picks the upcoming,
# still-bookable NY Kitchen class most worth promoting, drafts a social post in
# Echo (X + Bluesky) with the class image, and sends Rich an iOS push
# deep-linked to that draft so he can review and publish with one tap. Nothing
# auto-publishes: the draft sits in Echo until a human posts it.
#
# Off by default: sends nothing until Setting "class_promo:user_ids" lists at
# least one recipient user id (comma-separated). Runs hourly via
# config/recurring.yml; most runs send nothing. A send requires, in order:
#   - at least one enabled recipient
#   - under the daily budget (2) and a dice roll (sends 24/7; mute on the device)
#     (so the ~2 daily sends land at random daytime hours, not on the clock)
#   - the NYK workspace has active social accounts and a class worth promoting
#
# Complements CarsonNudgeJob's almost-sold-out nudge: that chases the last 1-2
# seats, this rotates through classes with open inventory that need a push.
#
# Manual test from prod console: ClassPromoDraftJob.perform_now(force: true)
class ClassPromoDraftJob < ApplicationJob
  queue_as :default

  DAILY_BUDGET            = 2
  SEND_CHANCE             = 0.35     # per eligible hourly run -> roughly 2/day
  ELIGIBLE_WINDOW_DAYS    = 14       # only promote classes within two weeks
  REPROMOTE_COOLDOWN_DAYS = 4        # don't re-promote the same class this soon

  def perform(force: false)
    users = enabled_users
    return if users.empty?
    return unless force || sendable_now?

    ws = Workspace.find_by(slug: "nykitchen")
    return unless ws
    platforms = ws.social_accounts.active.pluck(:platform).uniq
    return if platforms.empty?

    author = users.first
    event  = pick_class(ws)
    return unless event

    draft = draft_for(ws, event, platforms, author)
    return unless draft

    url = Rails.application.routes.url_helpers
               .edit_workspace_draft_path(workspace_slug: "nykitchen", id: draft.id)
    users.each do |user|
      Notification.notify!(
        level: :info, source: "sam",
        title: promo_title(event), body: promo_body(event),
        apns: true, apns_user: user, workspace: ws,
        apns_url: url, apns_subtitle: "Sam · Promote"
      )
    end
    Setting.increment(sent_today_key)
  end

  private

  def enabled_users
    ids = Setting.get("class_promo:user_ids").to_s.split(",").map(&:strip).reject(&:blank?)
    ids.empty? ? [] : User.where(id: ids).to_a
  end

  def sendable_now?
    Setting.counter(sent_today_key) < DAILY_BUDGET &&
      dice_roll < SEND_CHANCE
  end

  # Overridable for deterministic tests.
  def dice_roll = rand

  def sent_today_key = "class_promo:sent:#{Date.current.iso8601}"

  # The class most worth promoting: upcoming within the window, bookable,
  # public, and not promoted recently. Weighted so a class with open seats and
  # a nearer date outranks one that will sell itself; a small random tiebreak
  # keeps the rotation from being deterministic.
  #
  # Only reads scraped kitchen_events, so manually-added camp classes
  # (KitchenManualClass, a separate table) are never promoted -- camps don't
  # get social promotion. Don't reach into KitchenManualClass here.
  def pick_class(ws)
    snapshot = KitchenSnapshot.latest
    return nil unless snapshot

    snapshot.kitchen_events.upcoming
      .where("start_at <= ?", ELIGIBLE_WINDOW_DAYS.days.from_now)
      .to_a
      .reject { |e| e.sold_out? || e.private_event? }
      .reject { |e| e.spots_left && e.spots_left <= 0 }
      .reject { |e| recently_promoted?(ws, e) }
      .max_by { |e| promo_score(e) }
  end

  def promo_score(event)
    days         = [ (event.start_at.to_date - Date.current).to_i, 0 ].max
    urgency      = 1.0 / (days + 1)             # sooner = higher
    seats        = (event.spots_left || 6).to_f # unknown -> mild default
    seats_weight = Math.log10(seats + 1)        # more open seats = more to sell
    (urgency * 2.0) + seats_weight + (rand * 0.25)
  end

  # Skip a class we already have an open draft for, or that we drafted/posted
  # within the cooldown, so the rotation stays fresh instead of hammering one.
  def recently_promoted?(ws, event)
    return true if ws.workspace_drafts.exists?(source_url: event.url, status: %w[draft scheduled])

    since = REPROMOTE_COOLDOWN_DAYS.days.ago
    ws.workspace_drafts.where(source_url: event.url).where("created_at >= ?", since).exists? ||
      ws.workspace_posts.where(source_url: event.url).where("created_at >= ?", since).exists?
  end

  def draft_for(ws, event, platforms, author)
    body = KitchenAi::ClassPromoWriter.new(user: author).write(event).presence || template_body(event)
    body = with_booking_link(body, event.url)
    ws.workspace_drafts.create!(
      author:           author,
      body:             body,
      target_platforms: platforms,
      image_url:        event.image_url.presence,
      source_url:       event.url,
      link_card:        true, # post as a clickable link card so the photo opens signup
      status:           "draft"
    )
  rescue => e
    Rails.logger.error("ClassPromoDraftJob draft failed: #{e.class}: #{e.message}")
    nil
  end

  # Every class post carries the signup link so people can book. It also makes
  # X render the class page's preview card (clickable image). Appended in code
  # rather than trusted to the model, so the URL is always correct and present.
  def with_booking_link(body, url)
    return body if url.blank? || body.include?(url)
    "#{body}\n\n#{url}"
  end

  # Plain fallback when the AI writer returns nothing (same shape as the hub's
  # "Send to Echo" template and CarsonNudgeJob).
  def template_body(event)
    lines = [ "\u{1F373} #{event.name}", "",
              "\u{1F4C5} #{event.start_at.strftime('%A, %B %-d')}",
              "\u{23F0} #{event.start_at.strftime('%-l:%M %p')}" ]
    lines << "\u{1F4B2} $#{event.price} per person" if event.price.present?
    lines << "\u{1F4CD} New York Kitchen, Canandaigua"
    lines << ""
    lines << if event.spots_left && event.spots_left <= 6
      "Only #{event.spots_left} #{'seat'.pluralize(event.spots_left)} left, grab yours before it fills up!"
    else
      "Seats are open, come cook with us in the Finger Lakes!"
    end
    lines.join("\n")
  end

  def promo_title(event)
    "Promote #{event.name}"
  end

  def promo_body(event)
    when_str = event.start_at.strftime("%-m/%-d")
    if event.spots_left
      "#{event.spots_left} #{'seat'.pluralize(event.spots_left)} left for #{when_str}. Sam drafted a post in Echo, tap to review and publish."
    else
      "Sam drafted a post for #{when_str} in Echo. Tap to review and publish."
    end
  end
end
