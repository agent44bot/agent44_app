module Admin
  # Owner-only monthly plan: a checkable to-do list (June 2026: the Agent44
  # Labs DBA setup). Step completion lives in kv_settings as
  # "june_plan:done:<step_id>" = completion time, so checking off survives
  # deploys and shows when each step happened.
  class PlanController < BaseController
    OWNER_EMAIL = "botwhisperer@hey.com".freeze

    before_action :require_owner

    # The June 2026 plan. id must be stable (it keys the kv setting).
    PLAN = [
      {
        title: "Week 1: file the DBA",
        steps: [
          { id: "name_search", title: "Name search",
            detail: "Check Monroe County clerk assumed-name records and the NY DOS entity database for an Agent44 Labs conflict.",
            links: [
              { label: "Monroe County records (SearchIQS)", url: "https://searchiqs.com/nymonr/" },
              { label: "NY DOS entity search", url: "https://apps.dos.ny.gov/publicInquiry/" }
            ] },
          { id: "file_x201", title: "File Certificate of Assumed Name (form X-201)",
            detail: "Monroe County clerk (39 W. Main St, Room 101, Rochester), roughly $25 to $35. Get 2 or 3 certified copies; banks want one.",
            links: [
              { label: "DBA form (PDF)", url: "https://www.monroecounty.gov/files/clerk/DBA%20CERTIFICATE%20OF%20INDIVIDUAL%20v2.pdf" },
              { label: "Clerk DBA info", url: "https://www.monroecounty.gov/clerk-dba" }
            ] },
          { id: "ein", title: "Get an EIN",
            detail: "Free at irs.gov, about 10 minutes. Use it instead of your SSN on W-9s and bank forms.",
            links: [
              { label: "IRS EIN online application", url: "https://www.irs.gov/businesses/small-businesses-self-employed/apply-for-an-employer-identification-number-ein-online" }
            ] }
        ]
      },
      {
        title: "Week 2: money plumbing",
        steps: [
          { id: "bank_account", title: "Open the business checking account",
            detail: "Bring a certified DBA copy plus the EIN. Add a business credit card if offered." },
          { id: "move_expenses", title: "Move recurring business expenses to the new account",
            detail: "Anthropic/Claude Max, API usage, Fly.io, OpenRouter, GitHub, Apple Developer, domains." },
          { id: "receipts", title: "Gather receipts back to January 2026",
            detail: "Anthropic invoices, Apple, Fly, hardware, flights. Label each with its business purpose." }
        ]
      },
      {
        title: "Week 3: books and advice",
        steps: [
          { id: "books", title: "Set up bookkeeping",
            detail: "Wave (free) or a spreadsheet: income (NYK invoices) and categorized expenses. 30 minutes a month.",
            links: [ { label: "Wave", url: "https://www.waveapps.com" } ] },
          { id: "cpa", title: "Book the CPA consult",
            detail: "Three questions: profit-motive posture with W-2 offset losses; NY sales tax on SaaS subscriptions; when an LLC becomes worth it." }
        ]
      },
      {
        title: "Week 4: taxes forward",
        steps: [
          { id: "estimates", title: "Set up quarterly estimated taxes",
            detail: "Federal 1040-ES and NY IT-2105 if you expect to owe $1k or more. TurboTax Premium generates the vouchers.",
            links: [
              { label: "IRS 1040-ES", url: "https://www.irs.gov/forms-pubs/about-form-1040-es" },
              { label: "NY estimated tax", url: "https://www.tax.ny.gov/pit/estimated_tax/" }
            ] },
          { id: "home_office", title: "Measure the home office",
            detail: "Simplified deduction is $5 per square foot, up to 300 sq ft. One measurement, deduct every year." }
        ]
      }
    ].freeze

    def show
      @plan = PLAN
      @done = PLAN.flat_map { |s| s[:steps] }.to_h { |st| [ st[:id], Setting.time(done_key(st[:id])) ] }
      @total = @done.size
      @completed = @done.values.compact.size
    end

    # Toggle a step. Checking stores the timestamp; unchecking removes it.
    def toggle
      id = params[:step_id].to_s
      return head :unprocessable_entity unless PLAN.flat_map { |s| s[:steps] }.any? { |st| st[:id] == id }

      if Setting.time(done_key(id))
        Setting.delete_key(done_key(id))
      else
        Setting.touch_time(done_key(id))
      end
      redirect_to admin_plan_path
    end

    private

    def done_key(id)
      "june_plan:done:#{id}"
    end

    def require_owner
      unless Current.user&.email_address == OWNER_EMAIL
        redirect_to root_path, alert: "Not authorized."
      end
    end
  end
end
