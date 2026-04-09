namespace :jobs do
  desc "Re-run RoleClassifier over all jobs and update role_class + ai_augmented"
  task reclassify: :environment do
    total = Job.count
    changed = 0
    promoted_director = 0

    Job.find_each.with_index do |job, i|
      new_class = RoleClassifier.classify(
        title: job.title,
        description: job.description
      )
      next if new_class == job.role_class

      promoted_director += 1 if new_class == "agent_director"
      job.update_columns(
        role_class: new_class,
        ai_augmented: RoleClassifier.ai_flavored?(new_class),
        updated_at: Time.current
      )
      changed += 1

      print "." if (i % 200).zero?
    end

    puts
    puts "Reclassified #{changed} of #{total} jobs (#{promoted_director} new agent_director)."
    Rails.cache.delete_matched("jobs/ai_demand_meter/*") rescue nil
    Rails.cache.delete_matched("jobs/salary_stats/*") rescue nil
  end
end
