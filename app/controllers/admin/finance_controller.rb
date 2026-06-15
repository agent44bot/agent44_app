module Admin
  class FinanceController < BaseController
    # Rough planning reserve for taxes on net profit (SE tax + income + NY).
    # Not a precise calculation; see the note on the page.
    SET_ASIDE_RATE = 0.30

    # Whitelist of sortable expense columns (UI key => DB column). Kept as a
    # whitelist so the sort param can never inject arbitrary SQL.
    EXPENSE_SORTS = {
      "date"     => :incurred_on,
      "vendor"   => :vendor,
      "amount"   => :amount,
      "category" => :category,
      "excluded" => :excluded
    }.freeze

    def index
      @year = (params[:year] || Time.zone.now.year).to_i
      @years = available_years

      @sort = EXPENSE_SORTS.key?(params[:sort]) ? params[:sort] : "date"
      @dir  = params[:dir] == "asc" ? "asc" : "desc"
      col   = EXPENSE_SORTS[@sort]
      @expenses = Expense.for_year(@year).order(col => @dir.to_sym)
      # Stable secondary order by date so equal categories/flags don't shuffle.
      @expenses = @expenses.order(incurred_on: :desc) unless col == :incurred_on
      @category_totals = Expense.category_totals(@year).sort_by { |_, v| -v }
      @expense_total = Expense.year_total(@year)
      @flagged_count = Expense.for_year(@year).flagged.count

      @revenues = RevenueEntry.for_year(@year).order(received_on: :desc)
      @revenue_total = RevenueEntry.year_total(@year)

      @net_profit = @revenue_total - @expense_total
      @set_aside = [ @net_profit, 0 ].max * SET_ASIDE_RATE

      load_ai_spend
    end

    def import
      file = params[:file]
      if file.blank?
        redirect_to admin_finance_path, alert: "Choose a RocketMoney CSV to upload." and return
      end

      result = Finance::RocketMoneyImporter.new(file.read).import!
      notice = "Imported #{result.imported}, skipped #{result.skipped} duplicate(s), #{result.flagged} flagged for review."
      notice += " Errors: #{result.errors.join('; ')}" if result.errors.any?
      redirect_to admin_finance_path(year: params[:year]), notice: notice
    rescue ArgumentError => e
      redirect_to admin_finance_path, alert: e.message
    end

    def update_expense
      expense = Expense.find(params[:id])
      expense.update(expense_params)
      redirect_to admin_finance_path(year: expense.tax_year), notice: "Expense updated."
    end

    def create_revenue
      revenue = RevenueEntry.new(revenue_params)
      if revenue.save
        redirect_to admin_finance_path(year: revenue.tax_year), notice: "Revenue added."
      else
        redirect_to admin_finance_path, alert: revenue.errors.full_messages.join(", ")
      end
    end

    def destroy_revenue
      revenue = RevenueEntry.find(params[:id])
      revenue.destroy
      redirect_to admin_finance_path(year: revenue.tax_year), notice: "Revenue removed."
    end

    private

    # AI / Anthropic spend (merged in from the retired AI Costs page). This is
    # internal token spend, separate from the cash expense ledger above.
    def load_ai_spend
      month_start = Time.zone.now.beginning_of_month
      logs = AiCallLog.where("created_at >= ?", month_start)
      @ai_summary_by_source = AiCallLog.summary_by_source(logs)
      @ai_month_total = AiCallLog.total_cost_dollars(logs)
      @ai_nyk_month   = AiCallLog.total_cost_dollars(logs.where(source: AiCallLog::NYK_SOURCES))
      @ai_nyk_all     = AiCallLog.total_cost_dollars(AiCallLog.where(source: AiCallLog::NYK_SOURCES))
    end

    def available_years
      years = (Expense.distinct.pluck(:tax_year) + RevenueEntry.distinct.pluck(:tax_year)).compact.uniq
      years << Time.zone.now.year if years.empty?
      years.sort.reverse
    end

    def expense_params
      params.require(:expense).permit(:category, :business_purpose, :excluded, :vendor)
    end

    def revenue_params
      params.require(:revenue_entry).permit(:received_on, :source, :amount, :note)
    end
  end
end
