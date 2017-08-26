namespace :dockerized_app do

  # Helper Methods

  def docker_compose_opts
    ['-p', fetch(:application), '-f', 'docker-compose.yml', '-f', "docker-compose.#{fetch(:stage)}.yml"]
  end


  def upload_file(file, dest_path, options={})
    mod = options[:mod] || 'u+rw,go+r'
    own = options[:own]
    tmp_file = "#{fetch(:tmp_dir)}/#{Array.new(8) { [*'0'..'9'].sample }.join}"

    upload! file, tmp_file
    sudo :cp, '-f', tmp_file, dest_path
    sudo :chmod, mod, dest_path
    if own
      if own.include?(':')
        sudo :chown, own, dest_path
      else
        sudo :chown, "#{own}:$(id -gn #{own})", dest_path
      end
    end
    execute :rm, tmp_file
  end




  # Initial Setup Tasks

  task setup_initial: [:setup_init, :setup_log, :setup_cron, :setup_symlinks]


  task :setup_cron do
    on roles(:all) do
      upload_file('config/crontab', "/etc/cron.d/#{fetch(:application)}")
    end if File.exists?('config/crontab')

    on roles(:all, filter: :primary) do
      upload_file('config/crontab-primary', "/etc/cron.d/#{fetch(:application)}-primary")
    end if File.exists?('config/crontab-primary')
  end


  task :setup_init do
    init_script = <<-eos
#!/bin/sh

### BEGIN INIT INFO
# Provides:          #{fetch(:application)}
# Required-Start:    docker
# Required-Stop:     docker
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Dockerized app
# Description:       Dockerized app
### END INIT INFO

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin


case ${1} in
  start)
    cd #{current_path}
    docker-compose up -d
    ;;
  stop)
    cd #{current_path}
    docker-compose down
    ;;
  restart)
    ${0} stop
    ${0} start
    ;;
  *)
    echo "Usage: ${0} {start|stop|restart}"
    exit 1
esac
eos

    on roles(:all) do
      upload_file(StringIO.new(init_script), "/etc/init.d/#{fetch(:application)}", mod: 'u=rwx,go=rx')
      sudo :chkconfig, fetch(:application), 'on'
    end
  end


  task :setup_log do
    logrotate_script = <<-eos
#{shared_path}/log/*.log {
  daily
  rotate 5

  compress
  copytruncate
  delaycompress
  missingok
  notifempty
}
eos

    on roles(:all) do |host|
      sudo :mkdir, '-p', "#{shared_path}/log"
      sudo :chown, '-R', "#{host.user}:$(id -gn #{host.user})", fetch(:deploy_to)
      execute :chmod, '-R', 'u+rw,g+rws,o+r', fetch(:deploy_to)
      execute :chmod, 'o+w', "#{shared_path}/log"
      upload_file(StringIO.new(logrotate_script), "/etc/logrotate.d/#{fetch(:application)}")
    end
  end


  task :setup_symlinks do
    on roles(:all) do
      execute :ln, '-sf', current_path, "~/#{fetch(:application)}"
    end
  end




  # Deploy Tasks

  desc 'Deploy dockerized app'
  task deploy: [:check_setup_initial, :setup_compose, :setup_secrets, :build, :stop, :migrate, :start, :cleanup]

  after 'deploy:publishing', 'dockerized_app:deploy'


  task :check_setup_initial do
    on roles(:all) do
      if test "[ ! -f /etc/init.d/#{fetch(:application)} ] || [ ! -f /etc/logrotate.d/#{fetch(:application)} ]"
        invoke 'dockerized_app:setup_initial'
      end
    end
  end


  task :setup_compose do
    compose_env_file = <<-eos
COMPOSE_PROJECT_NAME=#{fetch(:application)}
COMPOSE_FILE=docker-compose.yml:docker-compose.#{fetch(:stage)}.yml
eos

    on roles(:all) do |host|
      upload_file(StringIO.new(compose_env_file), "#{current_path}/.env", mod: 'ug+rw,o+r', own: host.user)
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


  desc 'Build'
  task :build do
    on roles(:all) do
      within current_path do
        execute :'docker-compose', 'build'
      end
    end
  end


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


  desc 'Run command'
  task :run_command, :command do |t, args|
    on roles(:all) do
      within current_path do
        execute :'docker-compose', 'run', 'app', 'bash', '-c', "\"#{args[:command]}\""
      end
    end

    Rake::Task['dockerized_app:run_command'].reenable
  end


  desc 'Migrate'
  task :migrate do
    migrate_command = fetch(:dockerized_app_migrate_command)
    on roles(:all, filter: :primary) do
      invoke 'dockerized_app:run_command', migrate_command
    end if migrate_command
  end


  desc 'Cleanup'
  task :cleanup do
    on roles(:all) do
      execute :bash, '-c', '"for CONTAINER in \$(docker ps -f status=exited -q) ; do docker rm \${CONTAINER} ; done"'
      execute :bash, '-c', '"for IMAGE in \$(docker images -f dangling=true -q) ; do docker rmi \${IMAGE} ; done"'
      execute :docker, 'network', 'prune', '-f'
    end
  end




  # Uninstall Task

  desc 'Uninstall dockerized app'
  task :uninstall do
    on roles(:all) do
      if test "[ -L #{current_path} ] && [ -d $(readlink #{current_path}) ]"
        invoke 'dockerized_app:stop'
        invoke 'dockerized_app:cleanup'
      end

      sudo :rm, '-f', "/etc/init.d/#{fetch(:application)}", "/etc/logrotate.d/#{fetch(:application)}", "/etc/cron.d/{#{fetch(:application)},#{fetch(:application)}-primary}"
      execute :rm, '-f', "~/#{fetch(:application)}"
      execute :rm, '-fr', fetch(:deploy_to)
    end
  end

end
