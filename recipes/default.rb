include_recipe 'latest-git'
include_recipe 'latest-nodejs'
include_recipe 'modern_nginx'
include_recipe 'rbenv::default'
include_recipe 'rbenv::ruby_build'

id = 'aspyatkin-com'

data_bag = data_bag_item(id, node.chef_environment).to_hash

if node.chef_environment.start_with? 'development'
  node.default[id][:repository] = 'git@github.com:aspyatkin/aspyatkin.com.git'
  ssh_known_hosts_entry 'github.com'

  data_bag.fetch('ssh', {}).each do |key_type, key_contents|
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
  data_bag.fetch('git_config', {}).each do |key, value|
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

letsencrypt_dir = ::File.join base_dir, 'letsencrypt'

directory letsencrypt_dir do
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

data_bag.fetch('letsencrypt', {}).each do |fqdn, entries|
  letsencrypt_fqdn_dir = ::File.join letsencrypt_dir, fqdn

  directory letsencrypt_fqdn_dir do
    owner node[id][:user]
    group node[id][:group]
    mode 0755
    recursive true
    action :create
  end

  entries.each do |key, value|
    path = ::File.join letsencrypt_fqdn_dir, key
    file path do
      owner node[id][:user]
      group node[id][:group]
      mode 0644
      content value
      action :create
    end
  end
end

cert_dir = ::File.join node[:nginx][:dir], 'cert'

directory cert_dir do
  owner 'root'
  group node['root_group']
  mode 0700
  action :create
end

cert_entry = data_bag.fetch 'ssl', nil

cert_name = cert_entry['domains'][0]
ssl_certificate_path = ::File.join cert_dir, "#{cert_name}.chained.crt"

file ssl_certificate_path do
  owner 'root'
  group node['root_group']
  mode 0600
  content cert_entry['chain']
  action :create
end

ssl_certificate_key_path = ::File.join cert_dir, "#{cert_name}.key"

file ssl_certificate_key_path do
  owner 'root'
  group node['root_group']
  mode 0600
  content cert_entry['private_key']
  action :create
end

scts_dir = ::File.join node[:nginx][:dir], 'scts', cert_name

directory scts_dir do
  owner 'root'
  group node['root_group']
  mode 0700
  recursive true
  action :create
end

require 'base64'

data_bag.fetch('scts', {}).each do |name, data|
  path = ::File.join scts_dir, "#{name}.sct"
  file path do
    owner 'root'
    group node['root_group']
    mode 0644
    content Base64.decode64 data
    action :create
  end
end

nginx_conf = ::File.join node[:nginx][:dir], 'sites-available', "#{node[id][:fqdn]}.conf"

template nginx_conf do
  source 'nginx.conf.erb'
  mode 0644
  notifies :reload, 'service[nginx]', :delayed
  variables(
    fqdn: node[id][:fqdn],
    letsencrypt_root: letsencrypt_dir,
    ssl_certificate: ssl_certificate_path,
    ssl_certificate_key: ssl_certificate_key_path,
    hsts_max_age: node[id][:hsts_max_age],
    access_log: ::File.join(logs_dir, 'nginx_access.log'),
    error_log: ::File.join(logs_dir, 'nginx_error.log'),
    doc_root: ::File.join(base_dir, '_site'),
    oscp_stapling: node.chef_environment.start_with?('production'),
    scts: node.chef_environment.start_with?('production'),
    scts_dir: scts_dir,
    hpkp: node.chef_environment.start_with?('production'),
    hpkp_pins: data_bag.fetch('hpkp', []),
    hpkp_max_age: node[id][:hpkp_max_age]
  )
  action :create
end

nginx_site "#{node[id][:fqdn]}.conf"
