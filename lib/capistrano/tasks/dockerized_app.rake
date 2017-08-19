namespace :dockerized_app do

  # Helper Methods

  def docker_compose_opts
    ['-p', fetch(:application), '-f', 'docker-compose.yml', '-f', "docker-compose.#{fetch(:stage)}.yml"]
  end


  def upload_file(file, dest_path, options={})
    mod = options[:mod] || 'u+rw,go+r'
    tmp_file = "#{fetch(:tmp_dir)}/#{Array.new(8) { [*'0'..'9'].sample }.join}"

    upload! file, tmp_file
    sudo :cp, '-f', tmp_file, dest_path
    sudo :chmod, mod, dest_path
    execute :rm, tmp_file
  end




  # Setup Tasks

  desc 'Setup'
  task setup: [:setup_init, :setup_log, :setup_cron, :setup_symlinks]


  desc 'Setup cron'
  task :setup_cron do
    crontab = fetch(:dockerized_app_crontab)
    on roles(:all) do
      upload_file(crontab, "/etc/cron.d/#{fetch(:application)}")
    end if crontab

    crontab_primary = fetch(:dockerized_app_crontab_primary)
    on roles(:all, filter: :primary) do
      upload_file(crontab_primary, "/etc/cron.d/#{fetch(:application)}-primary")
    end if crontab_primary
  end


  desc 'Setup init'
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

DOCKER_COMPOSE_OPTS="#{docker_compose_opts.join(' ')}"


case ${1} in
  start)
    cd #{current_path}
    docker-compose ${DOCKER_COMPOSE_OPTS} up -d
    ;;
  stop)
    cd #{current_path}
    docker-compose ${DOCKER_COMPOSE_OPTS} down
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


  desc 'Setup log'
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


  desc 'Setup symlinks'
  task :setup_symlinks do
    on roles(:all) do
      execute :ln, '-sf', current_path, "~/#{fetch(:application)}"
    end
  end




  # Deploy Tasks

  desc 'deploy'
  task deploy: [:build, :stop, :migrate, :start, :cleanup]

  after 'deploy:publishing', 'dockerized_app:deploy'


  desc 'Build'
  task :build do
    on roles(:all) do
      within current_path do
        sudo :'docker-compose', *docker_compose_opts, 'build'
      end
    end
  end


  desc 'Start'
  task :start do
    on roles(:all) do
      within current_path do
        sudo :'docker-compose', *docker_compose_opts, 'up', '-d'
      end
    end
  end


  desc 'Stop'
  task :stop do
    on roles(:all) do
      within current_path do
        sudo :'docker-compose', *docker_compose_opts, 'down'
      end
    end
  end


  desc 'Restart'
  task restart: [:stop, :start]


  desc 'Run command'
  task :run_command, :command do |t, args|
    on roles(:all) do
      within current_path do
        sudo :'docker-compose', *docker_compose_opts, 'run', 'app', 'bash', '-c', "\"#{args[:command]}\""
      end
    end
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
      sudo :bash, '-c', '"for CONTAINER in \$(docker ps -f status=exited -q) ; do docker rm \${CONTAINER} ; done"'
      sudo :bash, '-c', '"for IMAGE in \$(docker images -f dangling=true -q) ; do docker rmi \${IMAGE} ; done"'
      sudo :docker, 'network', 'prune', '-f'
    end
  end

end
