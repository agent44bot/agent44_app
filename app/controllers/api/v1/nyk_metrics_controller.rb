module Api
  module V1
    class NykMetricsController < ApplicationController
      allow_unauthenticated_access
      skip_before_action :verify_authenticity_token, only: :filter_expanded

      def filter_expanded
        Setting.touch_time("nyk.filter_card_last_expanded_at")
        head :ok
      end
    end
  end
end
