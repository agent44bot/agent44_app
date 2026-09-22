module FeedbacksHelper
  # A feedback's page as a link target: only a local path ("/nykitchen/..."),
  # never an outside or javascript: URL, whatever ended up in the column.
  def feedback_page_path(feedback)
    path = feedback.page_url.to_s
    path.match?(%r{\A/(?![/\\])}) ? path : nil
  end
end
