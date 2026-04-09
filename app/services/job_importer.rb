class JobImporter
  attr_reader :created, :updated, :total

  def initialize(jobs_data)
    @jobs_data = jobs_data
    @created = 0
    @updated = 0
    @total = 0
  end

  def call
    @jobs_data.each do |jp|
      jp = jp.symbolize_keys if jp.respond_to?(:symbolize_keys)
      @total += 1

      next if JobSource.exists?(source: jp[:source], url: jp[:url])

      norm_title = Job.normalize_title(jp[:title])
      norm_company = Job.normalize_company(jp[:company])
      existing_job = Job.find_by(normalized_title: norm_title, normalized_company: norm_company) if norm_title.present?

      if existing_job
        existing_job.job_sources.create(
          source: jp[:source],
          url: jp[:url],
          external_id: jp[:external_id]
        )
        existing_job.update(description: jp[:description]) if existing_job.description.blank? && jp[:description].present?
        existing_job.update(salary: jp[:salary]) if existing_job.salary.blank? && jp[:salary].present?
        existing_job.update(location: jp[:location]) if existing_job.location.blank? && jp[:location].present?
        @updated += 1
      else
        role_class = RoleClassifier.classify(
          title: jp[:title],
          tags: jp[:tags],
          description: jp[:description]
        )
        job = Job.new(
          title: jp[:title],
          company: jp[:company],
          location: jp[:location],
          salary: jp[:salary],
          description: jp[:description],
          category: jp[:category],
          role_class: role_class,
          ai_augmented: RoleClassifier.ai_flavored?(role_class),
          source: jp[:source],
          url: jp[:url],
          external_id: jp[:external_id],
          posted_at: jp[:posted_at].present? ? Time.zone.parse(jp[:posted_at].to_s) : Time.current,
          active: true
        )
        if job.save
          job.job_sources.create!(
            source: jp[:source],
            url: jp[:url],
            external_id: jp[:external_id]
          )
          @created += 1
        end
      end
    end

    { created: @created, updated: @updated, total: @total }
  end
end
