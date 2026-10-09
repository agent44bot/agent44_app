module Admin
  # Edit the one-day personal note at the top of the 10am NY Kitchen digest
  # (KitchenDigestEmailJob.note_for), without a console or a deploy.
  class DigestNoteController < BaseController
    def show
      @heading = KitchenDigestEmailJob.note_heading
      @note    = Setting.get(KitchenDigestEmailJob::NOTE_KEY).to_s
      @note_on = Setting.get(KitchenDigestEmailJob::NOTE_ON_KEY).presence || default_date.iso8601
    end

    def update
      if params[:clear].present?
        Setting.delete_key(KitchenDigestEmailJob::NOTE_KEY)
        Setting.delete_key(KitchenDigestEmailJob::NOTE_ON_KEY)
        return redirect_to admin_digest_note_path, notice: "Note cleared."
      end

      note_on = Date.iso8601(params[:note_on].to_s)
      Setting.set(KitchenDigestEmailJob::NOTE_HEADING_KEY, params[:heading].to_s.strip)
      Setting.set(KitchenDigestEmailJob::NOTE_KEY, params[:note].to_s.strip)
      Setting.set(KitchenDigestEmailJob::NOTE_ON_KEY, note_on.iso8601)
      redirect_to admin_digest_note_path, notice: "Saved. Shows in the #{note_on.strftime('%a %b %-d')} 10am digest."
    rescue Date::Error
      redirect_to admin_digest_note_path, alert: "Pick a valid date."
    end

    # Today's real digest with the saved note (whatever its date), to the
    # signed-in admin only.
    def send_test
      digest, = KitchenDigestEmailJob.build_digest(Date.today)
      note = Setting.get(KitchenDigestEmailJob::NOTE_KEY).presence
      return redirect_to(admin_digest_note_path, alert: "No class data to build a digest from.") unless digest
      return redirect_to(admin_digest_note_path, alert: "Save a note first.") unless note

      mail = KitchenMailer.daily_digest(digest, recipients: [ Current.user.email_address ],
                                        note: note, note_heading: KitchenDigestEmailJob.note_heading)
      mail.subject = "[TEST] #{mail.subject}"
      mail.deliver_now
      redirect_to admin_digest_note_path, notice: "Test sent to #{Current.user.email_address}."
    end

    private

    # Before the 10am send, default to today; after it, tomorrow.
    def default_date
      now = Time.current
      now.hour < 10 ? now.to_date : now.to_date + 1
    end
  end
end
