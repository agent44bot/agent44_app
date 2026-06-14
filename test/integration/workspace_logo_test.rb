require "test_helper"

class WorkspaceLogoIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @owner  = User.create!(email_address: "wsl-o-#{SecureRandom.hex(4)}@example.com")
    @editor = User.create!(email_address: "wsl-e-#{SecureRandom.hex(4)}@example.com")
    @ws     = Workspace.create!(name: "Brand WS", owner: @owner)
    @ws.memberships.create!(user: @editor, role: "editor")
  end

  def png_upload
    fixture_file_upload("sample_bottle.png", "image/png")
  end

  def attach_existing_logo
    @ws.logo.attach(io: File.open(Rails.root.join("test/fixtures/files/sample_bottle.png")),
                    filename: "logo.png", content_type: "image/png")
  end

  test "owner can upload a brand logo and returns to where they were" do
    sign_in_as(@owner)
    assert_changes -> { @ws.reload.logo.attached? }, from: false, to: true do
      patch workspace_path(@ws.slug), params: { workspace: { logo: png_upload } },
            headers: { "HTTP_REFERER" => workspace_path(@ws.slug) }
    end
    # Returns to the submitting page, NOT the Social/Echo page (the reported bug).
    assert_redirected_to workspace_path(@ws.slug)
  end

  test "creating a workspace with a brand logo attaches it" do
    # Creating a workspace is site-admin gated during the dogfood phase.
    site_admin = User.create!(email_address: "wsl-sa-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    sign_in_as(site_admin)
    assert_difference -> { Workspace.count }, 1 do
      post workspaces_path, params: { workspace: { name: "Logo At Create", logo: png_upload } }
    end
    ws = Workspace.find_by(name: "Logo At Create")
    assert ws.logo.attached?, "logo uploaded on /new should attach at create"
  end

  test "editor (non-admin) cannot change the logo" do
    sign_in_as(@editor)
    patch workspace_path(@ws.slug), params: { workspace: { logo: png_upload } }
    refute @ws.reload.logo.attached?
    assert_match(/Only workspace admins/, flash[:alert])
  end

  test "owner can remove an existing logo" do
    attach_existing_logo
    sign_in_as(@owner)
    assert_changes -> { @ws.reload.logo.attached? }, from: true, to: false do
      patch workspace_path(@ws.slug), params: { workspace: { remove_logo: "1" } }
    end
  end

  test "the workspace overview shows the logo when one is attached" do
    attach_existing_logo
    sign_in_as(@owner)
    get workspace_path(@ws.slug)
    assert_response :success
    assert_select "img[alt=?]", "#{@ws.name} logo"
  end

  test "an admin (not just the owner) can upload the logo" do
    admin = User.create!(email_address: "wsl-a-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: admin, role: "admin")
    sign_in_as(admin)
    assert_changes -> { @ws.reload.logo.attached? }, from: false, to: true do
      patch workspace_path(@ws.slug), params: { workspace: { logo: png_upload } }
    end
  end

  test "uploading a non-image is rejected with an alert" do
    sign_in_as(@owner)
    bad = Rack::Test::UploadedFile.new(StringIO.new("nope"), "text/plain", original_filename: "x.txt")
    patch workspace_path(@ws.slug), params: { workspace: { logo: bad } }
    refute @ws.reload.logo.attached?
    assert_match(/Update failed/, flash[:alert])
  end
end
