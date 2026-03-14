class SchnorrVerifier
  def self.verify(message_hex:, pubkey_hex:, signature_hex:)
    message = [ message_hex ].pack("H*")
    public_key = [ pubkey_hex ].pack("H*")
    signature = [ signature_hex ].pack("H*")

    Schnorr.valid_sig?(message, public_key, signature)
  rescue StandardError => e
    Rails.logger.warn("Schnorr verification failed: #{e.message}")
    false
  end
end
