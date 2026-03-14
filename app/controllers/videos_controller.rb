class VideosController < ApplicationController
  allow_unauthenticated_access

  def index
    @videos = Video.published
  end

  def show
    @video = Video.find(params[:id])
  end
end
