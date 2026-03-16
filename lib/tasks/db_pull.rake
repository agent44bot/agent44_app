namespace :db do
  desc "Pull production SQLite database from Fly.io into local development"
  task pull: :environment do
    dev_db = Rails.root.join("storage/development.sqlite3")
    backup = Rails.root.join("storage/development.sqlite3.bak")
    tmp_file = Rails.root.join("storage/production_download.sqlite3")

    # Back up existing dev database
    if File.exist?(dev_db)
      puts "Backing up current dev database to #{backup}..."
      FileUtils.cp(dev_db, backup)
    end

    # Download from Fly.io
    puts "Downloading production database from Fly.io..."
    unless system("fly", "ssh", "sftp", "get", "/data/production.sqlite3", tmp_file.to_s)
      abort "Failed to download production database. Make sure you're authenticated with `fly auth login`."
    end

    # Replace dev database
    FileUtils.mv(tmp_file, dev_db)
    puts "Done! Production data is now in your local dev database."
    puts "Backup saved at #{backup}" if File.exist?(backup)
  end
end
