require_relative "base_page"

class DisplayPage < BasePage
  def visit
    super("/nykitchen/display")
  end

  def visit_with_token(token)
    super("/nykitchen/display?token=#{token}")
  end

  def slides
    page.query_selector_all("article.slide")
  end

  def slide_names
    page.query_selector_all("article.slide .name").map { |el| el.text_content.to_s.strip }
  end

  def header_text
    page.text_content(".brand")
  end
end
