# frozen_string_literal: true

# Picks a single engaging "morning question" for the Super Agent hub card,
# grounded in today's snapshot. The card renders this for free (no AI call) and
# links to /nykitchen/ask?q=<question>&go=1 so a click auto-asks the agent.
#
# Priority: a class about to sell out → fresh sold-outs → a date-rotating
# generic when nothing's notable. Data-aware entries update with each scrape;
# the fallback rotates once per calendar day.
module KitchenAi
  module MorningPrompt
    FALLBACKS = [
      "Give me a morning rundown — are the agents healthy, how are sales this week, and which classes are almost full?",
      "What sold out this week?",
      "Which classes are closest to selling out?",
      "How are weekend classes doing versus weekdays?"
    ].freeze

    module_function

    def question(today: Date.current)
      snap = KitchenSnapshot.latest
      return rotating(today) unless snap

      upcoming = snap.kitchen_events.upcoming.to_a

      # 1) A class about to sell out (1–3 seats left), soonest first.
      tight = upcoming.reject(&:sold_out?)
                      .select { |e| e.spots_left.to_i.between?(1, 3) }
                      .min_by { |e| e.start_at || (Time.current + 100.years) }
      if tight
        # NYK event names already embed the date (e.g. "Risotto Workshop 5/28/26"),
        # so we don't append one — it would read as a doubled date.
        n = tight.spots_left.to_i
        return %(The #{tight.name} is down to #{n} #{'seat'.pluralize(n)} — want a post to push it?)
      end

      # 2) Sold-out upcoming classes worth a waitlist nudge.
      sold = upcoming.count(&:sold_out?)
      return "#{sold} upcoming #{'class'.pluralize(sold)} #{sold == 1 ? 'is' : 'are'} sold out — want the list and some waitlist ideas?" if sold.positive?

      # 3) Nothing notable — rotate a generic, stable per calendar day.
      rotating(today)
    end

    # Julian day number gives a monotonic per-day index, so the generic question
    # changes once a day rather than per page load.
    def rotating(today)
      FALLBACKS[today.jd % FALLBACKS.size]
    end
  end
end
