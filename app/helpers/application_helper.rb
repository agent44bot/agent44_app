module ApplicationHelper
  def days_ago_in_words(date)
    return "recently" if date.nil?

    days = (Time.current.to_date - date.to_date).to_i

    case days
    when 0 then "today"
    when 1 then "1 day ago"
    else "#{days} days ago"
    end
  end
end
