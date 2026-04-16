namespace :test do
  desc "Run production smoke tests via bin/smoke (hits live endpoints)"
  task :smoke do
    filter = ARGV[1]
    cmd = filter ? "bin/smoke #{filter}" : "bin/smoke"
    exec cmd
  end
end
