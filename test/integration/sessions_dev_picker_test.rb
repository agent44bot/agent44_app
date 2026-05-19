require "test_helper"
require "minitest/mock"

# Covers the dev-only sign-in picker badges on /session/new. The picker is
# gated by Rails.env.development? and filters out @example.com emails, so
# the test stubs the env check and creates users with .test domains.
class SessionsDevPickerTest < ActionDispatch::IntegrationTest
  setup do
    # Site admin needed to own the workspaces we create below.
    @owner = User.create!(email_address: "owner-#{SecureRandom.hex(4)}@nyk.test", role: "admin")
  end

  test "admin user shows ADMIN badge" do
    user = User.create!(email_address: "alice-#{SecureRandom.hex(4)}@a44.test", role: "admin")
    rendered = get_dev_picker
    badge = extract_badge(rendered, user.email_address)
    assert_equal "admin", badge.downcase
  end

  test "reviewer user shows REVIEWER badge" do
    user = User.create!(email_address: "rev-#{SecureRandom.hex(4)}@a44.test", role: "reviewer")
    rendered = get_dev_picker
    badge = extract_badge(rendered, user.email_address)
    assert_equal "reviewer", badge.downcase
  end

  test "user with one workspace shows /slug badge" do
    user = User.create!(email_address: "lora-#{SecureRandom.hex(4)}@nyk.test", role: "user")
    ws   = Workspace.create!(name: "NY Kitchen", slug: "nyk-#{SecureRandom.hex(2)}", owner: @owner)
    ws.memberships.create!(user: user, role: "editor")

    rendered = get_dev_picker
    badge = extract_badge(rendered, user.email_address)
    assert_equal "/#{ws.slug}", badge.downcase
  end

  test "user with two workspaces shows /first-slug +1 badge" do
    user = User.create!(email_address: "lora2-#{SecureRandom.hex(4)}@multi.test", role: "user")
    ws1  = Workspace.create!(name: "NY Kitchen", slug: "ws1-#{SecureRandom.hex(2)}", owner: @owner)
    ws2  = Workspace.create!(name: "Magenta",    slug: "ws2-#{SecureRandom.hex(2)}", owner: @owner)
    ws1.memberships.create!(user: user, role: "editor")
    ws2.memberships.create!(user: user, role: "editor")

    rendered = get_dev_picker
    badge = extract_badge(rendered, user.email_address)
    # Order is whatever has_many :workspaces returns; just assert shape.
    assert_match %r{\A/(#{ws1.slug}|#{ws2.slug}) \+1\z}, badge.downcase
  end

  test "user with no workspaces shows USER badge" do
    user = User.create!(email_address: "vanilla-#{SecureRandom.hex(4)}@plain.test", role: "user")
    rendered = get_dev_picker
    badge = extract_badge(rendered, user.email_address)
    assert_equal "user", badge.downcase
  end

  private

  # GET /session/new with Rails.env stubbed to look like development, so the
  # dev picker actually renders.
  def get_dev_picker
    Rails.env.stub(:development?, true) do
      get new_session_path
    end
    assert_response :success
    response.body
  end

  # Find the user's row in the picker by their email, then extract the
  # adjacent badge text. The picker wraps each user in a <button> with the
  # email and badge as sibling spans; we cut from the email forward and
  # grab the first uppercase-styled label.
  def extract_badge(html, email)
    row = html[/#{Regexp.escape(email)}.*?(?=dev_login_as|<\/div>)/m]
    raise "Couldn't find row for #{email}" unless row
    m = row.match(/<span[^>]*uppercase[^>]*>\s*(.+?)\s*<\/span>/m)
    raise "Couldn't find badge in row for #{email}" unless m
    m[1].strip
  end
end
