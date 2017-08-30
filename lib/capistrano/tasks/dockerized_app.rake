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

end
