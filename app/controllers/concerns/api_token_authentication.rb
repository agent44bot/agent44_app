module ApiTokenAuthentication
  extend ActiveSupport::Concern

  private

  def authenticate_api_token
    token = request.headers["Authorization"]&.delete_prefix("Bearer ")
    api_token = ENV.fetch("API_TOKEN") { Rails.application.credentials.api_token }

    unless token.present? && api_token.present? && ActiveSupport::SecurityUtils.secure_compare(token, api_token)
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end
end
