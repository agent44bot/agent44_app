require "csv"

module Finance
  # Imports a RocketMoney transactions CSV (the "Agent44Labs" category export)
  # into Expense rows. Idempotent: re-uploading the same file skips rows that
  # already exist (matched by fingerprint). Only rows whose RocketMoney
  # Category is the business category are imported.
  class RocketMoneyImporter
    Result = Struct.new(:imported, :skipped, :flagged, :errors, keyword_init: true)

    BUSINESS_CATEGORY = "Agent44Labs".freeze

    def initialize(csv_text, business_category: BUSINESS_CATEGORY)
      @csv_text = csv_text
      @business_category = business_category
    end

    def import!
      imported = 0
      skipped = 0
      flagged = 0
      errors = []

      rows.each_with_index do |row, i|
        next unless row["Category"].to_s.strip.casecmp?(@business_category)

        date = parse_date(row["Date"] || row["Original Date"])
        amount = row["Amount"].to_f
        next if date.nil? || amount.zero?

        raw_vendor = row["Custom Name"].presence || row["Name"].presence || row["Description"]
        raw_description = row["Description"].presence || row["Name"]
        text = [ row["Name"], row["Custom Name"], row["Description"] ].compact.join(" ")

        fingerprint = Expense.fingerprint_for(
          incurred_on: date, vendor: raw_vendor, amount: amount, raw_description: raw_description
        )
        if Expense.exists?(fingerprint: fingerprint)
          skipped += 1
          next
        end

        c = ExpenseCategorizer.categorize(text, raw_vendor)
        expense = Expense.new(
          incurred_on: date,
          vendor: c[:vendor],
          raw_description: raw_description,
          amount: amount,
          category: c[:category],
          business_purpose: c[:business_purpose],
          source: "rocketmoney",
          review_flag: c[:review_flag],
          excluded: c[:excluded],
          fingerprint: fingerprint
        )
        if expense.save
          imported += 1
          flagged += 1 if expense.review_flag.present?
        else
          errors << "Row #{i + 2}: #{expense.errors.full_messages.join(', ')}"
        end
      end

      Result.new(imported: imported, skipped: skipped, flagged: flagged, errors: errors)
    end

    private

    def rows
      CSV.parse(@csv_text, headers: true)
    rescue CSV::MalformedCSVError => e
      raise ArgumentError, "Could not read the CSV: #{e.message}"
    end

    def parse_date(str)
      Date.parse(str.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
