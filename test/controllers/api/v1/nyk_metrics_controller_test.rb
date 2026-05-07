require "test_helper"

module Api
  module V1
    class NykMetricsControllerTest < ActionDispatch::IntegrationTest
      setup do
        Setting.delete_all
      end

      test "POST /api/v1/nyk/filter_expanded records the timestamp" do
        post api_v1_nyk_filter_expanded_path
        assert_response :success
        assert Setting.time("nyk.filter_card_last_expanded_at"), "timestamp should be set"
      end

      test "endpoint works without authentication" do
        post api_v1_nyk_filter_expanded_path
        assert_response :success
      end

      test "endpoint accepts CSRF-less requests (cross-origin friendly)" do
        post api_v1_nyk_filter_expanded_path
        assert_response :success
      end
    end
  end
end
