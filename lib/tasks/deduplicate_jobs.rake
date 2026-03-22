namespace :jobs do
  desc "Populate job_sources from existing jobs, set normalized fields, and merge duplicates"
  task deduplicate: :environment do
    puts "Step 1: Populating job_sources from existing jobs..."
    populated = 0
    Job.find_each do |job|
      next if job.source.blank? || job.url.blank?
      next if JobSource.exists?(source: job.source, url: job.url)

      JobSource.create!(
        job_id: job.id,
        source: job.source,
        url: job.url,
        external_id: job.external_id
      )
      populated += 1
    end
    puts "  Created #{populated} job_source records"

    puts "\nStep 2: Setting normalized fields on all jobs..."
    Job.find_each do |job|
      job.update_columns(
        normalized_title: Job.normalize_title(job.title),
        normalized_company: Job.normalize_company(job.company)
      )
    end
    puts "  Done"

    puts "\nStep 3: Finding and merging duplicate groups..."
    groups = Job.where.not(normalized_title: nil)
               .group(:normalized_title, :normalized_company)
               .having("COUNT(*) > 1")
               .count

    puts "  Found #{groups.size} duplicate groups"

    merged_count = 0
    groups.each do |(norm_title, norm_company), count|
      dupes = Job.where(normalized_title: norm_title, normalized_company: norm_company)
                 .order(:created_at)
                 .to_a

      primary = dupes.first
      dupes_to_merge = dupes[1..]

      dupes_to_merge.each do |dupe|
        # Move source records to primary job
        dupe.job_sources.each do |js|
          if JobSource.exists?(job_id: primary.id, source: js.source)
            js.destroy
          else
            js.update!(job_id: primary.id)
          end
        end

        # Reassign saved_jobs
        SavedJob.where(job_id: dupe.id).find_each do |sj|
          existing = SavedJob.find_by(user_id: sj.user_id, job_id: primary.id)
          if existing
            existing.update!(applied_at: sj.applied_at) if sj.applied_at && !existing.applied_at
            sj.destroy
          else
            sj.update!(job_id: primary.id)
          end
        end

        # Reassign hidden_jobs
        HiddenJob.where(job_id: dupe.id).find_each do |hj|
          if HiddenJob.exists?(user_id: hj.user_id, job_id: primary.id)
            hj.destroy
          else
            hj.update!(job_id: primary.id)
          end
        end

        # Enrich primary with data from dupe
        primary.update!(description: dupe.description) if primary.description.blank? && dupe.description.present?
        primary.update!(salary: dupe.salary) if primary.salary.blank? && dupe.salary.present?
        primary.update!(location: dupe.location) if primary.location.blank? && dupe.location.present?

        dupe.reload.destroy!
        merged_count += 1
      end

      sources = primary.job_sources.reload.pluck(:source).join(", ")
      puts "  Merged #{count} → 1: #{primary.title} @ #{primary.company} [#{sources}]"
    end

    puts "\nDone. Merged #{merged_count} duplicate records across #{groups.size} groups."
    puts "Total jobs now: #{Job.count}"
  end
end
