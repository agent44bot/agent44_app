namespace :newsletter do
  desc "Generate and publish a new newsletter post using Claude API"
  task generate: :environment do
    require "net/http"
    require "json"

    api_key = ENV.fetch("ANTHROPIC_API_KEY") do
      abort "ANTHROPIC_API_KEY is not set. Set it in your environment to generate newsletter posts."
    end

    telegram_bot_token = ENV["TELEGRAM_BOT_TOKEN"]
    telegram_chat_id = ENV["TELEGRAM_CHAT_ID"]

    # Gather context from recent jobs
    recent_jobs = Job.where("posted_at > ?", 30.days.ago).order(posted_at: :desc).limit(20)
    job_summary = recent_jobs.map { |j| "- #{j.title} at #{j.company} (#{j.category})" }.join("\n")

    ai_job_count = recent_jobs.ai_augmented.count
    traditional_count = recent_jobs.traditional.count

    # Gather unused news articles for context
    news_articles = NewsArticle.unused.recent.limit(15)
    news_summary = news_articles.map { |a|
      line = "- [#{a.source}] #{a.title}"
      line += " — #{a.summary.truncate(200)}" if a.summary.present?
      line
    }.join("\n")

    prompt = <<~PROMPT
      You are a newsletter writer for Agent44, an AI-augmented test automation consulting and SDET placement platform.

      Write a concise, engaging newsletter post about the current state of AI in test automation, QA engineering, and the job market for testers. The tone should be direct, opinionated, and practical — like advice from a senior QA engineer who's been in the trenches.

      Here is context from our job board (last 30 days):
      - Total recent postings: #{recent_jobs.count}
      - AI-augmented QA roles: #{ai_job_count}
      - Traditional test automation roles: #{traditional_count}
      #{job_summary.present? ? "\nRecent job titles:\n#{job_summary}" : ""}
      #{news_summary.present? ? "\nRecent AI testing industry news and articles:\n#{news_summary}\n\nUse the most interesting news items above to inform your writing. Reference specific tools, trends, or developments mentioned in the articles where relevant. Do not just list the articles — weave them into your narrative." : ""}

      Requirements:
      - Write in HTML (h2 for section headings, p tags for paragraphs, ul/ol for lists, strong/em for emphasis)
      - Do NOT include an h1 tag (the title is displayed separately)
      - Keep it between 600-900 words
      - Reference current trends, tools, or industry shifts happening in #{Date.current.strftime("%B %Y")}
      - Include actionable advice for QA professionals
      - Vary the topic each time — rotate between: job market trends, new AI testing tools, skills to learn, career pivots, industry news, automation strategy
      - End with a forward-looking statement

      Also provide a compelling title (under 80 characters) on the FIRST line, followed by a blank line, then the HTML body. Do not wrap the title in any tags.
    PROMPT

    puts "Generating newsletter post via Claude API..."

    uri = URI("https://api.anthropic.com/v1/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.ca_file = ENV.fetch("SSL_CERT_FILE", nil)
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    request = Net::HTTP::Post.new(uri)
    request["x-api-key"] = api_key
    request["anthropic-version"] = "2023-06-01"
    request["content-type"] = "application/json"
    request.body = {
      model: "claude-sonnet-4-6",
      max_tokens: 2048,
      messages: [ { role: "user", content: prompt } ]
    }.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      abort "Claude API error (#{response.code}): #{response.body}"
    end

    result = JSON.parse(response.body)
    content = result.dig("content", 0, "text")

    if content.blank?
      abort "Claude API returned empty content"
    end

    # Parse title and body
    lines = content.strip.split("\n", 2)
    title = lines[0].strip.gsub(/^#\s*/, "")
    body = lines[1].to_s.strip

    # Create the post
    user = User.find_by(email_address: "agent44@agent44.com") || User.first
    abort "No user found to assign the post to" unless user

    post = user.posts.create!(
      title: title,
      body: body,
      published: true,
      published_at: Time.current
    )

    # Mark news articles as used
    if news_articles.any?
      news_articles.each(&:mark_as_used!)
      puts "Marked #{news_articles.count} news articles as used"
    end

    puts "Published: \"#{post.title}\" (slug: #{post.slug})"
    puts "URL: /pulse/#{post.slug}"

    # Send Telegram notification
    if telegram_bot_token.present? && telegram_chat_id.present?
      app_url = ENV.fetch("APP_URL", "https://agent44.com")
      post_url = "#{app_url}/pulse/#{post.slug}"
      preview = post.body.to_plain_text.truncate(200)
      telegram_text = "💓 *New Pulse Published*\n\n*#{post.title}*\n\n#{preview}\n\n[Read the full post](#{post_url})"

      tg_uri = URI("https://api.telegram.org/bot#{telegram_bot_token}/sendMessage")
      tg_http = Net::HTTP.new(tg_uri.host, tg_uri.port)
      tg_http.use_ssl = true
      tg_req = Net::HTTP::Post.new(tg_uri)
      tg_req["content-type"] = "application/json"
      tg_req.body = { chat_id: telegram_chat_id, text: telegram_text, parse_mode: "Markdown" }.to_json

      tg_response = tg_http.request(tg_req)
      if tg_response.is_a?(Net::HTTPSuccess)
        puts "Telegram notification sent!"
      else
        puts "Telegram notification failed (#{tg_response.code}): #{tg_response.body}"
      end
    else
      puts "TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set — skipping Telegram notification"
    end
  end
end
