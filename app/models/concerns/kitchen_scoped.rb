# Kitchen records belong to a workspace (NY Kitchen first, any kitchen-enabled
# workspace after the multi-tenant refactor).
#
# Transitional default (slice 1): a record created without a workspace lands
# in NY Kitchen, because every existing writer (jobs, the scrape API, the
# smoke workflow) predates tenancy and all kitchen data so far is NYK's. Slice
# 3 makes every writer pass the workspace, then drops this default and makes
# the column NOT NULL. New code must always set workspace explicitly.
module KitchenScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :workspace, optional: true
    before_validation :default_workspace_to_nyk, on: :create
  end

  private

  def default_workspace_to_nyk
    self.workspace ||= Workspace.nykitchen
  end
end
