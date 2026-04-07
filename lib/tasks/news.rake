namespace :newsletter do
  desc "Gather recent AI testing news from external sources"
  task gather_news: :environment do
    require "net/http"
    require "json"
    require "rexml/document"

    SEARCH_QUERIES = [
      "AI testing tools",
      "AI test automation",
      "LLM testing",
      "AI QA engineering",
      "AI software testing",
      "machine learning testing tools"
    ].freeze

    total_saved = 0
    total_skipped = 0

    # --- Google News RSS ---
    puts "Fetching from Google News RSS..."
    SEARCH_QUERIES.each do |query|
      encoded = URI.encode_www_form_component(query)
      url = "https://news.google.com/rss/search?q=#{encoded}+when:7d&hl=en-US&gl=US&ceid=US:en"

      begin
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = 15
        response = http.request(Net::HTTP::Get.new(uri))

        next unless response.is_a?(Net::HTTPSuccess)

        doc = REXML::Document.new(response.body)
        doc.elements.each("rss/channel/item") do |item|
          title = item.elements["title"]&.text
          link = item.elements["link"]&.text
          pub_date = item.elements["pubDate"]&.text
          description = item.elements["description"]&.text

          next unless title && link

          summary = if description
            description.gsub(/<[^>]+>/, "").strip.truncate(500)
          end

          published_at = begin
            Time.parse(pub_date)
          rescue
            nil
          end

          article = NewsArticle.find_or_initialize_by(url: link)
          if article.new_record?
            article.assign_attributes(
              title: title.truncate(255),
              source: "google_news",
              summary: summary,
              published_at: published_at
            )
            if article.save
              total_saved += 1
            end
          else
            total_skipped += 1
          end
        end
      rescue => e
        puts "  Google News error for '#{query}': #{e.message}"
      end
    end

    # --- Dev.to ---
    puts "Fetching from Dev.to..."
    %w[testing ai automation qa].each do |tag|
      begin
        uri = URI("https://dev.to/api/articles?tag=#{tag}&top=7&per_page=10")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = 15
        response = http.request(Net::HTTP::Get.new(uri))

        next unless response.is_a?(Net::HTTPSuccess)

        articles = JSON.parse(response.body)
        articles.each do |a|
          next unless a["title"] && a["url"]

          # Filter for testing/QA relevance
          text = "#{a["title"]} #{a["description"]} #{a["tag_list"]&.join(" ")}".downcase
          next unless text.match?(/test|qa|quality|automat|sdet/i)

          article = NewsArticle.find_or_initialize_by(url: a["url"])
          if article.new_record?
            article.assign_attributes(
              title: a["title"].truncate(255),
              source: "devto",
              summary: a["description"]&.truncate(500),
              published_at: a["published_at"] ? Time.parse(a["published_at"]) : nil
            )
            if article.save
              total_saved += 1
            end
          else
            total_skipped += 1
          end
        end
      rescue => e
        puts "  Dev.to error for tag '#{tag}': #{e.message}"
      end
    end

    # --- Hacker News (Algolia API) ---
    puts "Fetching from Hacker News..."
    %w[AI+testing LLM+testing test+automation].each do |query|
      begin
        # Stories from the last 7 days
        timestamp = (Time.current - 7.days).to_i
        uri = URI("https://hn.algolia.com/api/v1/search_by_date?query=#{query}&tags=story&numericFilters=created_at_i>#{timestamp}&hitsPerPage=10")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = 15
        response = http.request(Net::HTTP::Get.new(uri))

        next unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        (data["hits"] || []).each do |hit|
          title = hit["title"]
          link = hit["url"].presence || "https://news.ycombinator.com/item?id=#{hit["objectID"]}"

          next unless title

          article = NewsArticle.find_or_initialize_by(url: link)
          if article.new_record?
            article.assign_attributes(
              title: title.truncate(255),
              source: "hackernews",
              summary: hit["story_text"]&.gsub(/<[^>]+>/, "")&.truncate(500),
              published_at: hit["created_at"] ? Time.parse(hit["created_at"]) : nil
            )
            if article.save
              total_saved += 1
            end
          else
            total_skipped += 1
          end
        end
      rescue => e
        puts "  Hacker News error for '#{query}': #{e.message}"
      end
    end

    puts "Done! Saved #{total_saved} new articles, skipped #{total_skipped} duplicates."
    puts "Total unused articles: #{NewsArticle.unused.count}"

    # --- Generate daily digest via Haiku ---
    today = Time.current.to_date
    todays_articles = NewsArticle.where(
      published_at: today.beginning_of_day..today.end_of_day
    ).order(published_at: :desc)

    # Fall back to most recent articles if none published today
    if todays_articles.empty?
      todays_articles = NewsArticle.order(published_at: :desc).limit(20)
    end

    if todays_articles.any? && !NewsDigest.exists?(date: today)
      api_key = ENV["ANTHROPIC_API_KEY"]
      if api_key.present?
        puts "Generating daily digest via Haiku..."

        article_list = todays_articles.limit(20).map { |a|
          line = "- #{a.title} (#{a.source})"
          line += " — #{a.summary.truncate(150)}" if a.summary.present?
          line += " [URL: #{a.url}]"
          line
        }.join("\n")

        prompt = <<~PROMPT
          You are a concise news editor for an AI testing and QA engineering audience.

          Given these articles, pick the 5 most interesting and relevant ones for QA engineers and test automation professionals. Write exactly 5 bullet points summarizing the key takeaway from each.

          Format each bullet as:
          - **Takeaway summary in one sentence.** [Read more](URL)

          Use the actual article URL from the list below. Be direct and practical — what should a QA engineer know or care about?

          Articles:
          #{article_list}
        PROMPT

        uri = URI("https://api.anthropic.com/v1/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri)
        request["x-api-key"] = api_key
        request["anthropic-version"] = "2023-06-01"
        request["content-type"] = "application/json"
        request.body = {
          model: "claude-haiku-4-5-20251001",
          max_tokens: 1024,
          messages: [{ role: "user", content: prompt }]
        }.to_json

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          result = JSON.parse(response.body)
          summary = result.dig("content", 0, "text")

          if summary.present?
            NewsDigest.create!(date: today, summary: summary)
            puts "Daily digest created for #{today}"
          else
            puts "Haiku returned empty content — skipping digest"
          end
        else
          puts "Haiku API error (#{response.code}): #{response.body}"
        end
      else
        puts "ANTHROPIC_API_KEY not set — skipping daily digest generation"
      end
    elsif NewsDigest.exists?(date: today)
      puts "Digest already exists for #{today} — skipping"
    else
      puts "No articles to digest — skipping"
    end
  end
end
