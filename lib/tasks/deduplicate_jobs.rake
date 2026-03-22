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

    puts "\nStep 3: Finding and merging exact duplicate groups..."
    merged_count = merge_duplicate_groups
    puts "  Merged #{merged_count} records"

    puts "\nStep 4: Fuzzy title matching (strip company/location from titles)..."
    fuzzy_merged = merge_fuzzy_title_groups
    puts "  Merged #{fuzzy_merged} records"

    puts "\nDone. Total jobs now: #{Job.count}"
  end
end

def merge_duplicate_groups
  groups = Job.where.not(normalized_title: nil)
             .group(:normalized_title, :normalized_company)
             .having("COUNT(*) > 1")
             .count

  puts "  Found #{groups.size} exact duplicate groups"
  merged_count = 0

  groups.each do |(norm_title, norm_company), count|
    dupes = Job.where(normalized_title: norm_title, normalized_company: norm_company)
               .order(:created_at)
               .to_a

    merged_count += merge_jobs(dupes)
  end

  merged_count
end

def merge_fuzzy_title_groups
  # Extract the core job title (before first " - ") for looser matching
  # This catches cases like "Senior SDET - Eccalon LLC - Detroit, MI" vs "Senior SDET - Eccalon - Hanover, MD"
  jobs_by_core = {}
  Job.active.includes(:job_sources).find_each do |job|
    core_title = extract_core_title(job.normalized_title)
    next if core_title.blank? || core_title.length < 10

    key = core_title
    jobs_by_core[key] ||= []
    jobs_by_core[key] << job
  end

  merged_count = 0
  jobs_by_core.each do |core_title, jobs|
    next if jobs.size < 2

    # Group by similar company (strip suffixes and compare)
    company_groups = jobs.group_by { |j| normalize_company_loose(j.company) }
    company_groups.each do |company, group|
      next if group.size < 2
      puts "  Fuzzy match: \"#{core_title}\" @ #{company} (#{group.size} jobs)"
      merged_count += merge_jobs(group.sort_by(&:created_at))
    end
  end

  merged_count
end

def extract_core_title(normalized_title)
  return nil if normalized_title.blank?
  # Take the part before the first " - " (which is usually where company/location starts)
  parts = normalized_title.split(" - ")
  core = parts.first&.strip
  # If the core is too short or is the whole title, return nil
  core.present? && core != normalized_title ? core : nil
end

def normalize_company_loose(company)
  return "" if company.blank?
  company.downcase.strip
    .gsub(/,?\s*(inc\.?|llc\.?|corp\.?|ltd\.?|co\.?|company|corporation|incorporated)\s*$/i, "")
    .gsub(/[^a-z0-9]/, "") # strip all non-alphanumeric for loose matching
end

def merge_jobs(sorted_jobs)
  return 0 if sorted_jobs.size < 2

  primary = sorted_jobs.first
  dupes_to_merge = sorted_jobs[1..]
  merged = 0

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
    merged += 1
  end

  sources = primary.job_sources.reload.pluck(:source).join(", ")
  puts "    → #{primary.title} @ #{primary.company} [#{sources}]"

  merged
end
