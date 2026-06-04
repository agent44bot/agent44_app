module CredentialsTestHelper
  # Temporarily make Rails.application.credentials.dig return a fixed value
  # (or nil) inside the block. Used to test ENV/credentials fallback paths
  # without touching the encrypted file. We use define_singleton_method
  # because Minitest's .stub() doesn't yield reliably on
  # ActiveSupport::EncryptedConfiguration (its method_missing intercepts).
  def with_credentials_dig(return_value)
    creds = Rails.application.credentials
    creds.define_singleton_method(:dig) { |*_args| return_value }
    yield
  ensure
    creds.singleton_class.send(:remove_method, :dig) rescue nil
  end
end
