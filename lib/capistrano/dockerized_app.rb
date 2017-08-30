rake_files = %w[
  dockerized_app
  initial_setup_tasks
  setup_deploy_tasks
  deploy_tasks
  maintenance_tasks
]

rake_files.each { |f| load File.expand_path("../tasks/#{f}.rake", __FILE__) }
