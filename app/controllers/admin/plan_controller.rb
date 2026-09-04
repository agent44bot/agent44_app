module Admin
  # Owner-only plans: checkable to-do lists. Step completion lives in
  # kv_settings as "<plan key>:done:<step_id>" = completion time, so checking
  # off survives deploys and shows when each step happened.
  #
  # PLANS is newest-first; the first entry is the default view. Each plan's
  # :key prefixes its kv settings (the June plan keeps its original "june_plan"
  # key so existing check-offs survive). Step ids must be stable.
  class PlanController < BaseController
    OWNER_EMAIL = "botwhisperer@hey.com".freeze

    before_action :require_owner

    GROWTH_2027 = {
      slug: "growth-2027",
      key: "growth_2027",
      title: "2027 growth plan",
      tab: "2027 growth",
      subtitle: "Agent44 Labs: from one client to a business",
      intro: "Where things stand going in: NYK is the one paying client, Gems of Eden is warming up, and the fleet " \
             "(Scout, Argus, Echo, Fleet Social, the Sunday owner report) is proven in prod. The three that matter " \
             "most: finish multi-tenant, close Brian, ask Lora for two intros. Everything else follows from three " \
             "logos and self-serve onboarding.",
      footer: "Target: five paying clients by mid-2027 (about $15K/yr at $200 plus usage), enough to prove the model. " \
              "Ten is when it starts to matter. Let the pipeline decide whether the second half is more clients or higher prices.",
      sections: [
        {
          title: "Q1: foundation",
          steps: [
            { id: "multitenant", title: "Finish the multi-tenant refactor",
              detail: "This is the growth bottleneck. Every client that needs a nykitchen-specific code path costs a weekend. " \
                      "A new signup should get a scraper source, social connections, and a report schedule with no PR. " \
                      "Never break /nykitchen/display or /print." },
            { id: "bundle", title: "Productize what NYK already pays for",
              detail: "Package the fleet as a fixed-price tier: about $200/month retainer plus metered usage. One-page offer: " \
                      "calendar and inventory monitoring, social drafting and posting, weekly owner report, website smoke tests. " \
                      "Sell the bundle, not custom work." },
            { id: "nyk_2027_billing", title: "Add the retainer to NYK's 2027 invoices",
              detail: "Fixed monthly dev and support line alongside the per-run and per-token usage lines. Confirm the number " \
                      "before Lora sees it. Do not touch 2026 invoices." },
            { id: "invoicing", title: "Real invoicing flow from the billing page",
              detail: "Generate and send invoices from the NYK billing page instead of by hand. Decide on an LLC before revenue " \
                      "passes a few clients so 2027 taxes stay simple." }
          ]
        },
        {
          title: "Q1 to Q2: first three logos",
          steps: [
            { id: "gems_of_eden", title: "Close Gems of Eden (Brian) as client two",
              detail: "Lead with the draft-from-image social flow. Price low for the first three months. Two logos in one region " \
                      "is a pattern; one is a favor." },
            { id: "lora_intros", title: "Ask Lora for two warm intros",
              detail: "Wineries, breweries, event venues, and farm stands within an hour of Canandaigua all know each other. " \
                      "Go vertical (Finger Lakes food and drink) before going wide." },
            { id: "sales_deck", title: "Testimonial plus a sample Sunday report",
              detail: "That is the whole sales deck. Ask Lora for a two-sentence quote and use a redacted weekly report as the leave-behind." }
          ]
        },
        {
          title: "Products that sell themselves",
          steps: [
            { id: "echo_entry", title: "Lead with the cheap, sticky agents",
              detail: "Echo (social listening plus drafted replies) and the weekly owner report are low-token, high-visibility, " \
                      "and hard to cancel once an owner is used to them. Entry product first, then upsell scrapes, tests, and posting." },
            { id: "argus_qa", title: "Sell Argus-style QA to the day-job network",
              detail: "Monthly smoke and regression testing as a service for small SaaS shops and agencies. Same infrastructure, " \
                      "second product line, and it plays to a credential already held." }
          ]
        },
        {
          title: "Marketing without a sales team",
          steps: [
            { id: "publish_numbers", title: "Publish the numbers monthly",
              detail: "\"960 scrapes for $329\" beats anything about AI. Post cost per run, tokens, and pass rates through Fleet Social " \
                      "on X and Bluesky so the product markets itself." },
            { id: "referrals", title: "Referral: one free month per converted intro",
              detail: "At this scale word of mouth from Lora and Brian beats any ad spend." }
          ]
        }
      ]
    }.freeze

    JUNE_2026 = {
      slug: "june-2026",
      key: "june_plan",
      title: "June 2026 plan",
      tab: "June 2026 DBA",
      subtitle: "Agent44Labs DBA setup",
      intro: "Step by step to a sole-proprietor DBA with clean, deductible books.",
      footer: "Reference: deduct everything since Jan 2026 on the 2026 Schedule C (TurboTax Premium handles it). " \
              "The DBA does not create deductions; it makes them defensible.",
      sections: [
        {
          title: "Week 1: file the DBA",
          steps: [
            { id: "name_search", title: "Name search",
              detail: "Check Monroe County clerk assumed-name records and the NY DOS entity database for an Agent44Labs conflict.",
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
              detail: "Online-only works: sign up with the EIN plus a scan of the DBA certificate. Found is built for sole props (auto Schedule C categories); Novo and BlueVine are solid free checking. Skip Cash App (payments app, not a bank account).",
              links: [
                { label: "Found", url: "https://found.com" },
                { label: "Novo", url: "https://www.novo.co" },
                { label: "BlueVine", url: "https://www.bluevine.com" }
              ] },
            { id: "move_expenses", title: "Point recurring expenses at the business card",
              detail: "Get a business credit card (Chase Ink or Amex Business; apply with the DBA name and EIN), put Anthropic/Claude Max, API usage, Fly.io, OpenRouter, GitHub, Apple Developer, and domains on it, and autopay the card from the business checking. Business-only spend on the card; charges deduct in the year charged." },
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
      ]
    }.freeze

    PLANS = [ GROWTH_2027, JUNE_2026 ].freeze

    def show
      @plans = PLANS
      @plan = find_plan(params[:plan]) || PLANS.first
      steps = @plan[:sections].flat_map { |s| s[:steps] }
      @done = steps.to_h { |st| [ st[:id], Setting.time(done_key(@plan, st[:id])) ] }
      @total = @done.size
      @completed = @done.values.compact.size
    end

    # Toggle a step. Checking stores the timestamp; unchecking removes it.
    # Legacy callers without a plan param resolve to the June plan, which
    # was the only plan when the toggle route shipped.
    def toggle
      plan = params[:plan].present? ? find_plan(params[:plan]) : JUNE_2026
      id = params[:step_id].to_s
      return head :unprocessable_entity unless plan && plan[:sections].flat_map { |s| s[:steps] }.any? { |st| st[:id] == id }

      if Setting.time(done_key(plan, id))
        Setting.delete_key(done_key(plan, id))
      else
        Setting.touch_time(done_key(plan, id))
      end
      redirect_to admin_plan_path(plan: plan[:slug])
    end

    private

    def find_plan(slug)
      PLANS.find { |p| p[:slug] == slug.to_s }
    end

    def done_key(plan, id)
      "#{plan[:key]}:done:#{id}"
    end

    def require_owner
      unless Current.user&.email_address == OWNER_EMAIL
        redirect_to root_path, alert: "Not authorized."
      end
    end
  end
end
