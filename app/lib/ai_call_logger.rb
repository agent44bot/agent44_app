# Captures token counts off an Anthropic SDK response and writes a row to
# ai_call_logs. Best-effort — logging failures are swallowed so a billing
# bug never breaks the user-visible feature that triggered the call.
class AiCallLogger
  def self.log!(response, model:, source:, user: nil, workspace: nil)
    usage = extract_usage(response)
    return if usage.nil?

    AiCallLog.create!(
      model:         model,
      source:        source,
      input_tokens:  usage[:input_tokens].to_i,
      output_tokens: usage[:output_tokens].to_i,
      user:          user,
      workspace:     workspace
    )
  rescue => e
    Rails.logger.error("AiCallLogger.log! failed for source=#{source}: #{e.class}: #{e.message}")
    nil
  end

  def self.extract_usage(response)
    if response.respond_to?(:usage) && response.usage
      { input_tokens: response.usage.input_tokens, output_tokens: response.usage.output_tokens }
    elsif response.is_a?(Hash) && response[:usage]
      { input_tokens: response.dig(:usage, :input_tokens), output_tokens: response.dig(:usage, :output_tokens) }
    end
  end
end
