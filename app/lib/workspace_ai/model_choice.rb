# Per-workspace Anthropic model selection for a workspace's AI features
# (Social Agent drafts, Connect Help Chat). Owners/admins pick a model per
# feature on the workspace AI usage page; the choice is stored in Setting (kv)
# via AiModelChoice, scoped by workspace id so each workspace is independent.
# Call sites resolve their model through here, falling back to the feature's
# code default (Haiku) when no override is saved. Mirrors NY Kitchen's
# AiModelChoice, scoped per workspace.
module WorkspaceAi
  module ModelChoice
    # Selectable AI features on a workspace -> label for the billing UI. The
    # key matches the AiCallLog `source` each feature logs under.
    FEATURES = {
      "workspace_ai_assist" => "Social Agent drafts",
      "connect_help_chat"   => "Connect Help Chat"
    }.freeze

    # Setting source key for a workspace + feature, e.g. "ws:12:connect_help_chat".
    def self.source(workspace, feature)
      "ws:#{workspace.id}:#{feature}"
    end

    # Full model id for a feature: saved override, else the call site's default.
    def self.resolve(workspace, feature, default:)
      AiModelChoice.resolve(source(workspace, feature), default: default)
    end

    # Selected model key (opus/sonnet/haiku) for the UI; defaults to haiku.
    def self.selected_key(workspace, feature)
      AiModelChoice.selected_key(source(workspace, feature))
    end

    def self.set(workspace, feature, key)
      AiModelChoice.set(source(workspace, feature), key)
    end
  end
end
