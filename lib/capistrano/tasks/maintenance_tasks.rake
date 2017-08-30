namespace :dockerized_app do

  # Maintenance Tasks

  desc 'Cleanup'
  task :cleanup do
    on roles(:all) do
      execute :bash, '-c', '"for CONTAINER in \$(docker ps -f status=exited -q) ; do docker rm \${CONTAINER} ; done"'
      execute :bash, '-c', '"for IMAGE in \$(docker images -f dangling=true -q) ; do docker rmi \${IMAGE} ; done"'
      execute :docker, 'network', 'prune', '-f'
    end
  end


  desc 'Uninstall dockerized app'
  task :uninstall do
    on roles(:all) do
      if test "[ -L #{current_path} ] && [ -d $(readlink #{current_path}) ]"
        invoke 'dockerized_app:stop'
        invoke 'dockerized_app:cleanup'
      end

      sudo :rm, '-f', "/etc/init.d/#{fetch(:application)}", "/etc/cron.d/{#{fetch(:application)},#{fetch(:application)}-primary}", "/etc/logrotate.d/#{fetch(:application)}"
      execute :rm, '-f', "~/#{fetch(:application)}"
      execute :rm, '-fr', fetch(:deploy_to)
    end
  end

end
