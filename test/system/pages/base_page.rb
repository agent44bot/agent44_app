class BasePage
  attr_reader :page

  def initialize(page, base_url)
    @page = page
    @base_url = base_url
  end

  def visit(path)
    page.goto("#{@base_url}#{path}")
  end

  def title
    page.title
  end

  def body_text
    page.text_content("body")
  end

  def current_url
    page.url
  end

  def response_status
    page.evaluate("() => window.performance.getEntriesByType('navigation')[0]?.responseStatus || 200")
  end
end
