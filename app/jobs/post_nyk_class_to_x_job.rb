require "anthropic"

# Daily cron: pick one upcoming non-sold-out NYK class that we haven't already
# tweeted (or drafted), generate a 280-char post via Claude Haiku, save it as
# a draft on social_post_logs, and ping Rich for approval. The actual tweet
# only goes out when Rich opens the approval page and taps "Post to X".
class PostNykClassToXJob < ApplicationJob
  queue_as :default

  TWEET_MAX = XClient::MAX_TWEET_LENGTH

  def perform
    return unless ENV["X_AUTOPOST_ENABLED"].to_s == "true"

    snapshot = KitchenSnapshot.order(taken_on: :desc).first
    return unless snapshot

    event = pick_event(snapshot)
    return unless event

    draft = build_tweet_text(event)
    return unless draft

    log = SocialPostLog.find_or_initialize_by(event_url: event.url)
    log.x_draft_text     = draft
    log.x_drafted_at     = Time.current
    log.x_approval_token = SecureRandom.urlsafe_base64(16)
    log.save!

    notify_for_approval(event, log)
  end

  private

  def pick_event(snapshot)
    eligible = snapshot.kitchen_events.upcoming.reject { |e| e.sold_out? }
    return nil if eligible.empty?

    posted_or_drafted_urls = SocialPostLog
      .where("x_post_id IS NOT NULL OR x_drafted_at IS NOT NULL")
      .pluck(:event_url)

    fresh = eligible.reject { |e| posted_or_drafted_urls.include?(e.url) }
    fresh.sample
  end

  def build_tweet_text(event)
    api_key = ENV["ANTHROPIC_API_KEY"]
    return nil if api_key.blank?

    client = Anthropic::Client.new(api_key: api_key)
    prompt = tweet_prompt(event)

    response = client.messages.create(
      model: "claude-haiku-4-5-20251001",
      max_tokens: 300,
      messages: [ { role: "user", content: prompt } ]
    )

    text = response.content.first.text.to_s.strip
    text = text.gsub(/\A["']|["']\z/, "")
    text[0, TWEET_MAX]
  rescue => e
    Rails.logger.error("PostNykClassToXJob: AI generation failed: #{e.class}: #{e.message}")
    nil
  end

  def tweet_prompt(event)
    date_str = event.start_at&.strftime("%a %b %-d") || "soon"
    <<~PROMPT
      Write a single tweet (max #{TWEET_MAX} characters, hard limit) inviting people to a culinary class at New York Kitchen in Canandaigua, NY (Finger Lakes).

      Voice: warm, inviting, like a friend telling you about something fun. Use 1–2 emojis at most. No hashtag spam — one or two topical hashtags max.

      Include the class name, the date, and the URL.

      Class: #{event.name}
      Date: #{date_str}
      URL: #{event.url}
      Description: #{event.description.to_s[0, 400]}

      Return ONLY the tweet text. No quotes, no commentary.
    PROMPT
  end

  def notify_for_approval(event, log)
    approval_url = "/nykitchen/x_drafts/#{log.x_approval_token}"
    recipients = User.where(role: %w[admin kitchen_customer]).where.not(email_address: nil)

    # Telegram fires once (it's a global broadcast).
    Notification.notify!(
      level: "info",
      source: "x_autopost",
      title: "Tweet draft: #{event.name}",
      body: "Tap to review and approve before it posts to @agent44bot.",
      telegram: true,
      apns: false
    )

    # Per-user iOS push so each recipient's badge ticks up.
    recipients.each do |user|
      Notification.notify!(
        level: "info",
        source: "x_autopost",
        title: "Tweet draft: #{event.name}",
        body: "Tap to review and approve before it posts to @agent44bot.",
        telegram: false,
        apns: true,
        apns_url: approval_url,
        apns_user: user
      )
    end
  end
end
