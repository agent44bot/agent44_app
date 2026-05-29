class AddCoverLetterToJobMatches < ActiveRecord::Migration[8.0]
  def change
    add_column :job_matches, :cover_letter, :text
    add_column :job_matches, :cover_letter_at, :datetime
  end
end
