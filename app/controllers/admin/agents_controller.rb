module Admin
  class AgentsController < BaseController
    before_action :set_agent, only: %i[edit update destroy]

    def index
      @agents = Agent.ordered
    end

    def new
      @agent = Agent.new(status: "offline", avatar_color: "orange", position: Agent.maximum(:position).to_i + 1)
    end

    def create
      @agent = Agent.new(agent_params)
      if @agent.save
        redirect_to admin_agents_path, notice: "#{@agent.name} created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @agent.update(agent_params)
        redirect_to admin_agents_path, notice: "#{@agent.name} updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @agent.destroy
      redirect_to admin_agents_path, notice: "Agent deleted."
    end

    private

    def set_agent
      @agent = Agent.find(params[:id])
    end

    def agent_params
      params.require(:agent).permit(:name, :role, :description, :status, :avatar_color, :position, :llm_model, :schedule)
    end
  end
end
