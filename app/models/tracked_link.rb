# A stable, trackable redirect for a QR code. The QR encodes /nykitchen/r/:token
# instead of the raw destination, so a scan lands on us first (logged as a
# LinkScan) and then 302s onward. Keyed by a digest of the URL, not a DB id,
# because the daily snapshot regenerates KitchenEvent rows: a flyer stapled to
# the wall must keep resolving all week even as the underlying rows churn.
class TrackedLink < ApplicationRecord
  belongs_to :workspace, optional: true
  has_many :link_scans, dependent: :destroy

  validates :url, presence: true
  validates :token, presence: true, uniqueness: true

  # Deterministic short token for a URL. Same URL always maps to the same
  # token, so we can find-or-create without a lookup table.
  def self.token_for(url)
    Digest::SHA256.hexdigest(url.to_s)[0, 12]
  end

  # The trackable link for a destination URL, created on first use.
  def self.for_url(url, workspace: nil)
    token = token_for(url)
    find_or_create_by!(token: token) do |link|
      link.url = url
      link.workspace = workspace
    end
  rescue ActiveRecord::RecordNotUnique
    # Concurrent first-render race: the other request won, just read it back.
    find_by!(token: token)
  end
end
