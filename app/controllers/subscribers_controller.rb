class SubscribersController < ApplicationController
  allow_unauthenticated_access

  def create
    @subscriber = Subscriber.new(email: params[:email])
    if @subscriber.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to root_path, notice: "Thanks for subscribing!" }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("newsletter_form", partial: "subscribers/form", locals: { error: @subscriber.errors.full_messages.first }) }
        format.html { redirect_to root_path, alert: @subscriber.errors.full_messages.first }
      end
    end
  end
end
