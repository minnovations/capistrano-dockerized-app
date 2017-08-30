namespace :dockerized_app do

  # Deploy Tasks

  desc 'Deploy dockerized app'
  task deploy: [:setup_initial_check, :setup_deploy, :build, :stop, :migrate, :start, :cleanup]

  after 'deploy:publishing', 'dockerized_app:deploy'


  #

  task :build do
    on roles(:all) do
      within current_path do
        execute :'docker-compose', 'build'
      end
    end
  end


  #

  desc 'Start'
  task :start do
    on roles(:all) do
      within current_path do
        execute :'docker-compose', 'up', '-d'
      end
    end
  end


  desc 'Stop'
  task :stop do
    on roles(:all) do
      within current_path do
        execute :'docker-compose', 'down'
      end
    end
  end


  desc 'Restart'
  task restart: [:stop, :start]


  #

  desc 'Exec command'
  task :exec_command, :command do |t, args|
    on roles(:all) do
      within current_path do
        execute :'docker-compose', 'exec', 'app', 'bash', '-c', "\"#{args[:command]}\""
      end
    end

    Rake::Task['dockerized_app:exec_command'].reenable
  end


  desc 'Run command'
  task :run_command, :command do |t, args|
    on roles(:all) do
      within current_path do
        execute :'docker-compose', 'run', 'app', 'bash', '-c', "\"#{args[:command]}\""
      end
    end

    Rake::Task['dockerized_app:run_command'].reenable
  end


  #

  desc 'Migrate'
  task :migrate do
    migrate_command = fetch(:dockerized_app_migrate_command)
    on roles(:all, filter: :primary) do
      invoke 'dockerized_app:run_command', migrate_command
    end if migrate_command
  end

end
