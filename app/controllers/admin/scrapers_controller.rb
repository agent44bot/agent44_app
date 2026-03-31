module Admin
  class ScrapersController < BaseController
    before_action :set_scraper, only: %i[show edit update destroy run]

    def index
      @scrapers = ScraperSource.order(:name)
    end

    def show
    end

    def new
      @scraper = ScraperSource.new(schedule: "every_6h")
    end

    def create
      @scraper = ScraperSource.new(scraper_params)
      if @scraper.save
        redirect_to admin_scraper_path(@scraper), notice: "Scraper created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @scraper.update(scraper_params)
        redirect_to admin_scraper_path(@scraper), notice: "Scraper updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @scraper.destroy
      redirect_to admin_scrapers_path, notice: "Scraper deleted."
    end

    def run
      result = @scraper.run!
      if result[:error]
        redirect_to admin_scraper_path(@scraper), alert: "Scraper failed: #{result[:error]}"
      else
        redirect_to admin_scraper_path(@scraper), notice: "Scraper ran successfully: #{result[:created]} created, #{result[:updated]} updated (#{result[:total]} found)"
      end
    end

    private

    def set_scraper
      @scraper = ScraperSource.find(params[:id])
    end

    def scraper_params
      permitted = params.require(:scraper_source).permit(:name, :slug, :enabled, :source_url, :api_key_name, :schedule, :search_terms_text, :config_text)

      # Convert search_terms from newline-separated text to JSON array
      if permitted[:search_terms_text].present?
        permitted[:search_terms] = permitted.delete(:search_terms_text).split("\n").map(&:strip).reject(&:blank?)
      else
        permitted.delete(:search_terms_text)
      end

      # Convert config from text to JSON hash
      if permitted[:config_text].present?
        begin
          permitted[:config] = JSON.parse(permitted.delete(:config_text))
        rescue JSON::ParserError
          permitted.delete(:config_text)
        end
      else
        permitted.delete(:config_text)
      end

      permitted
    end
  end
end
