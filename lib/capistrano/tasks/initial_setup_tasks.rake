namespace :dockerized_app do

  # Initial Setup Tasks

  task setup_initial: [:setup_init, :setup_logrotate, :setup_symlinks]


  task :setup_initial_check do
    on roles(:all) do
      if test "[ ! -f /etc/init.d/#{fetch(:application)} ]"
        invoke 'dockerized_app:setup_initial'
      end
    end
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


  task :setup_logrotate do
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
      upload_file(StringIO.new(logrotate_script), "/etc/logrotate.d/#{fetch(:application)}")
    end
  end


  task :setup_symlinks do
    on roles(:all) do
      execute :ln, '-sf', current_path, "~/#{fetch(:application)}"
    end
  end

end
