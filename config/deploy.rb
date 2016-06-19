# config valid only for current version of Capistrano
lock '3.5.0'

set :image_name, 'dockertest'
set :account, 'whazzmaster'

namespace :deploy do
  task :docker do
    on roles(:docker) do |host|
      image_name = fetch(:image_name)
      account = fetch(:account)

      puts "============= Starting Docker Update ============="
      execute "docker stop #{image_name}; echo 0"
      execute "docker rm -f #{image_name}; echo 0"
      execute "docker pull #{account}/#{image_name}:latest"
      execute "docker run -p 80:80 -d --name #{image_name} #{account}/#{image_name}:latest"
    end
  end
end
