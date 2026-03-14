module Admin
  class VideosController < BaseController
    before_action :set_video, only: %i[edit update destroy]

    def index
      @videos = Video.order(position: :asc, created_at: :desc)
    end

    def new
      @video = Video.new
    end

    def create
      @video = Video.new(video_params)
      if @video.save
        redirect_to admin_videos_path, notice: "Video added."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @video.update(video_params)
        redirect_to admin_videos_path, notice: "Video updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @video.destroy
      redirect_to admin_videos_path, notice: "Video deleted."
    end

    private

    def set_video
      @video = Video.find(params[:id])
    end

    def video_params
      params.require(:video).permit(:title, :youtube_id, :youtube_url, :description, :position, :published)
    end
  end
end
