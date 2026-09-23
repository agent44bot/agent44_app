require_relative "system_test_helper"

# Dropping files on the Send feedback form: allowed types are added to the
# file input, anything else is skipped with a note. The form POST is caught
# in the browser (never reaches the server), so no feedback row is saved and
# no push/email job runs.
class FeedbackDropzoneSystemTest < SystemTestCase
  setup do
    @user = User.find_or_create_by!(email_address: "dropzone@feedback.test") do |u|
      u.password = "password123"
    end
    @user.update!(feedback_access: true)
  end

  test "dropping a valid and an invalid file submits only the valid one" do
    @page.goto("#{BASE_URL}/session/new")
    @page.fill("input[name='email_address']", @user.email_address)
    @page.fill("input[name='password']",      "password123")
    @page.click("button[type='submit']")
    sleep 0.5

    @page.goto("#{BASE_URL}/feedback/new")
    @page.wait_for_selector("[data-controller='feedback-dropzone']")

    @page.evaluate(<<~JS)
      () => {
        const dt = new DataTransfer()
        dt.items.add(new File(["hello"], "notes.txt", { type: "text/plain" }))
        dt.items.add(new File(["MZ"], "setup.exe", { type: "application/octet-stream" }))
        const zone = document.querySelector("[data-controller='feedback-dropzone']")
        zone.dispatchEvent(new DragEvent("drop", { dataTransfer: dt, bubbles: true, cancelable: true }))
      }
    JS

    names = @page.evaluate("() => Array.from(document.querySelector('input[type=file]').files).map(f => f.name)")
    assert_equal [ "notes.txt" ], names
    assert_match(/Skipped: setup\.exe/, @page.text_content("[data-feedback-dropzone-target='note']"))

    posted = nil
    @page.route("**/feedbacks", ->(route, request) {
      posted = request.post_data_buffer.to_s
      route.fulfill(status: 200, body: "ok")
    })
    @page.fill("textarea[name='feedback[message]']", "Dropzone test")
    @page.click("input[type='submit']")
    20.times { break if posted; sleep 0.1 }

    assert posted, "Expected the form to POST"
    assert_includes posted, 'filename="notes.txt"'
    refute_includes posted, "setup.exe"
  end
end
