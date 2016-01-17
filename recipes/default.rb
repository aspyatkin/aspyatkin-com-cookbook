include_recipe 'latest-git::default'
include_recipe 'latest-nodejs::default'
include_recipe 'modern_nginx::default'
include_recipe 'modern_nginx::cert'
include_recipe 'rbenv::default'
include_recipe 'rbenv::ruby_build'

id = 'aspyatkin-com'

if node.chef_environment.start_with? 'development'
  node.default[id][:repository] = 'git@github.com:aspyatkin/aspyatkin.com.git'
  ssh_known_hosts_entry 'github.com'

  data_bag_item(id, node.chef_environment).to_hash.fetch('ssh', {}).each do |key_type, key_contents|
    ssh_user_private_key key_type do
      key key_contents
      user node[id][:user]
    end
  end
end

base_dir = ::File.join '/var/www', node[id][:fqdn]

directory base_dir do
  owner node[id][:user]
  group node[id][:group]
  mode 0755
  recursive true
  action :create
end

git base_dir do
  repository node[id][:repository]
  revision node[id][:revision]
  enable_checkout false
  user node[id][:user]
  group node[id][:group]
  action :sync
end

if node.chef_environment.start_with? 'development'
  data_bag_item(id, node.chef_environment).to_hash.fetch('git_config', {}).each do |key, value|
    git_config key do
      value value
      scope 'local'
      path base_dir
      user node[id][:user]
      action :set
    end
  end
end

logs_dir = ::File.join base_dir, 'logs'

directory logs_dir do
  owner node[id][:user]
  group node[id][:group]
  mode 0755
  recursive true
  action :create
end

ENV['CONFIGURE_OPTS'] = '--disable-install-rdoc'

rbenv_ruby '2.2.3' do
  ruby_version '2.2.3'
  global true
end

rbenv_gem 'bundler' do
  ruby_version '2.2.3'
end

rbenv_execute "Install bundle at #{base_dir}" do
  command 'bundle'
  ruby_version '2.2.3'
  cwd base_dir
  user node[id][:user]
  group node[id][:group]
end

rbenv_execute 'Build website' do
  command 'jekyll build'
  ruby_version '2.2.3'
  cwd base_dir
  user node[id][:user]
  group node[id][:group]
  environment 'JEKYLL_ENV' => node.chef_environment
end

nginx_conf = ::File.join node[:nginx][:dir], 'sites-available', "#{node[id][:fqdn]}.conf"

template nginx_conf do
  Chef::Resource::Template.send(:include, ::ModernNginx::Helper)
  source 'nginx.conf.erb'
  mode 0644
  notifies :reload, 'service[nginx]', :delayed
  variables(
    fqdn: node[id][:fqdn],
    acme_challenge: node.chef_environment.start_with?('production'),
    acme_challenge_directories: {
      "#{node[id][:fqdn]}" => get_acme_challenge_directory(node[id][:fqdn]),
      "www.#{node[id][:fqdn]}" => get_acme_challenge_directory("www.#{node[id][:fqdn]}")
    },
    ssl_certificate: get_ssl_certificate_path(node[id][:fqdn]),
    ssl_certificate_key: get_ssl_certificate_private_key_path(node[id][:fqdn]),
    hsts_max_age: node[id][:hsts_max_age],
    access_log: ::File.join(logs_dir, 'nginx_access.log'),
    error_log: ::File.join(logs_dir, 'nginx_error.log'),
    doc_root: ::File.join(base_dir, '_site'),
    oscp_stapling: node.chef_environment.start_with?('production'),
    scts: node.chef_environment.start_with?('production'),
    scts_dir: get_scts_directory(node[id][:fqdn]),
    hpkp: node.chef_environment.start_with?('production'),
    hpkp_pins: get_hpkp_pins(node[id][:fqdn]),
    hpkp_max_age: node[id][:hpkp_max_age]
  )
  action :create
end

nginx_site "#{node[id][:fqdn]}.conf"
