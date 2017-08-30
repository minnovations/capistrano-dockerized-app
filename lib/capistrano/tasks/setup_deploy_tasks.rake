namespace :dockerized_app do

  # Setup Deploy Tasks

  task setup_deploy: [:setup_compose, :setup_host_volume_mounts, :setup_secrets, :setup_cron]


  task :setup_compose do
    compose_env_file = <<-eos
COMPOSE_PROJECT_NAME=#{fetch(:application)}
COMPOSE_FILE=docker-compose.yml:docker-compose.#{fetch(:stage)}.yml
eos

    on roles(:all) do |host|
      upload_file(StringIO.new(compose_env_file), "#{current_path}/.env", mod: 'ug+rw,o+r', own: host.user)
    end
  end


  task :setup_cron do
    on roles(:all) do
      upload_file('config/crontab', "/etc/cron.d/#{fetch(:application)}")
    end if File.exists?('config/crontab')

    on roles(:all, filter: :primary) do
      upload_file('config/crontab-primary', "/etc/cron.d/#{fetch(:application)}-primary")
    end if File.exists?('config/crontab-primary')
  end


  task :setup_host_volume_mounts do
    # Relative to deploy_to
    mounts = Array(fetch(:dockerized_app_host_volume_mounts, 'shared/log'))

    on roles(:all) do
      mounts.each do |mount|
        mount_path = "#{fetch(:deploy_to)}/#{mount}"
        execute :mkdir, '-p', mount_path
        sudo :chown, fetch(:dockerized_app_user, 'app'), mount_path
      end
    end
  end


  task :setup_secrets do
    on roles(:all) do
      if test "[ -f #{current_path}/.env.d/.env.secrets.asc ]"
        within current_path do
          execute :cp, '.env.d/.env.secrets.asc', '.env.d/.env.secrets'
        end
      end
    end
  end

end
