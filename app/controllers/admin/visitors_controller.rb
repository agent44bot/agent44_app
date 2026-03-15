module Admin
  class VisitorsController < BaseController
    def map
      @visitors = PageView.with_location
                          .where(created_at: 30.days.ago..Time.current)
                          .select(:latitude, :longitude, :city, :country, :path, :created_at, :device_type, :browser)
                          .order(created_at: :desc)
                          .limit(500)

      @visitor_count = @visitors.size
      @country_count = @visitors.map(&:country).uniq.compact.size
    end
  end
end
