require "digest"

namespace :db do
  desc "Pull production SQLite database from Fly.io into local development"
  task pull: :environment do
    app           = "agent44-app"
    dev_db        = Rails.root.join("storage/development.sqlite3")
    dev_wal       = Rails.root.join("storage/development.sqlite3-wal")
    dev_shm       = Rails.root.join("storage/development.sqlite3-shm")
    backup        = Rails.root.join("storage/development.sqlite3.bak")
    tmp_file      = Rails.root.join("storage/production_download.sqlite3")
    snapshot_path = "/data/snapshot.sqlite3"

    # Without a .backup snapshot, sftp grabs the live file while Rails is
    # mid-write — main file is incomplete because pending pages live in
    # production.sqlite3-wal. SQLite's .backup flushes everything into one
    # consistent file. Run it on prod first.
    puts "Taking consistent snapshot on prod..."
    unless system("fly", "ssh", "console", "-a", app, "-C",
                  %(sqlite3 /data/production.sqlite3 ".backup #{snapshot_path}"))
      abort "Snapshot failed. If you see ssh-certificate errors, run `fly ssh issue --agent personal` and retry."
    end

    puts "Checking snapshot integrity..."
    integrity = `fly ssh console -a #{app} -C "sqlite3 #{snapshot_path} 'PRAGMA integrity_check;'"`.strip
    abort "Integrity check failed: #{integrity[0, 200]}" unless integrity == "ok"

    puts "Reading prod checksum..."
    prod_md5 = `fly ssh console -a #{app} -C "md5sum #{snapshot_path}"`.strip.split(/\s+/).first
    abort "Could not capture prod md5 (got #{prod_md5.inspect})." unless prod_md5.to_s.match?(/\A[0-9a-f]{32}\z/)
    puts "  prod md5: #{prod_md5}"

    if File.exist?(dev_db)
      puts "Backing up current dev database to #{backup}..."
      FileUtils.cp(dev_db, backup)
    end

    File.delete(tmp_file) if File.exist?(tmp_file)
    puts "Downloading snapshot..."
    unless system("fly", "ssh", "sftp", "get", "-a", app, snapshot_path, tmp_file.to_s)
      abort "Download failed."
    end

    local_md5 = Digest::MD5.file(tmp_file).hexdigest
    if prod_md5 != local_md5
      File.delete(tmp_file) if File.exist?(tmp_file)
      abort "Checksum mismatch — sftp transfer corrupted. prod=#{prod_md5} local=#{local_md5}. Re-run the task."
    end
    puts "  local md5: #{local_md5} ✓"

    # Stale -wal / -shm sidecars from the previous dev DB will collide with
    # the new main file (different page hashes). The Ruby sqlite3 gem will
    # report "malformed database schema" even though the file itself is
    # fine. Wipe before swapping.
    File.delete(dev_wal) if File.exist?(dev_wal)
    File.delete(dev_shm) if File.exist?(dev_shm)
    FileUtils.mv(tmp_file, dev_db)

    puts "Cleaning up snapshot on prod..."
    system("fly", "ssh", "console", "-a", app, "-C", "rm #{snapshot_path}")

    puts ""
    puts "Done — production data is now in your local dev database."
    puts "Backup saved at #{backup}" if File.exist?(backup)
  end
end
