include_recipe 'latest-git::default'
include_recipe 'latest-nodejs::default'
include_recipe 'modern_nginx::default'
include_recipe 'rbenv::default'
include_recipe 'rbenv::ruby_build'

id = 'aspyatkin-com'

repository_url = "https://github.com/#{node[id]['github_repository']}"

if node.chef_environment.start_with? 'development'
  ssh_private_key node[id]['user']
  ssh_known_hosts_entry 'github.com'
  repository_url = "git@github.com:#{node[id]['github_repository']}.git"
end

base_dir = ::File.join '/var/www', node[id]['fqdn']

directory base_dir do
  owner node[id]['user']
  group node[id]['group']
  mode 0755
  recursive true
  action :create
end

git base_dir do
  repository repository_url
  revision node[id]['revision']
  enable_checkout false
  user node[id]['user']
  group node[id]['group']
  action :sync
end

if node.chef_environment.start_with? 'development'
  git_config = data_bag_item('git', node.chef_environment).to_hash.fetch(
    'config',
    {}
  )

  git_config.each do |key, value|
    git_config key do
      value value
      scope 'local'
      path base_dir
      user node[id]['user']
      action :set
    end
  end
end

logs_dir = ::File.join base_dir, 'logs'

directory logs_dir do
  owner node[id]['user']
  group node[id]['group']
  mode 0755
  recursive true
  action :create
end

ENV['CONFIGURE_OPTS'] = '--disable-install-rdoc'

rbenv_ruby node[id]['ruby_version'] do
  ruby_version node[id]['ruby_version']
  global true
end

rbenv_gem 'bundler' do
  ruby_version node[id]['ruby_version']
  version node[id]['bundler_version']
end

rbenv_execute "Install bundle at #{base_dir}" do
  command 'bundle'
  ruby_version node[id]['ruby_version']
  cwd base_dir
  user node[id]['user']
  group node[id]['group']
end

rbenv_execute 'Build website' do
  command 'jekyll build'
  ruby_version node[id]['ruby_version']
  cwd base_dir
  user node[id]['user']
  group node[id]['group']
  environment 'JEKYLL_ENV' => node.chef_environment
end

ngx_conf = "#{node[id]['fqdn']}.conf"

tls_certificate node[id]['fqdn']
tls_item = ::ChefCookbook::TLS.new(node).certificate_entry node[id]['fqdn']

template ::File.join(node['nginx']['dir'], 'sites-available', ngx_conf) do
  source 'nginx.conf.erb'
  mode 0644
  notifies :reload, 'service[nginx]', :delayed
  variables(
    fqdn: node[id]['fqdn'],
    ssl_certificate: tls_item.certificate_path,
    ssl_certificate_key: tls_item.certificate_private_key_path,
    hsts_max_age: node[id]['hsts_max_age'],
    access_log: ::File.join(logs_dir, 'nginx_access.log'),
    error_log: ::File.join(logs_dir, 'nginx_error.log'),
    doc_root: ::File.join(base_dir, '_site'),
    oscp_stapling: node.chef_environment.start_with?('production'),
    scts: node.chef_environment.start_with?('production'),
    scts_dir: tls_item.scts_dir,
    hpkp: node.chef_environment.start_with?('production'),
    hpkp_pins: tls_item.hpkp_pins,
    hpkp_max_age: node[id]['hpkp_max_age']
  )
  action :create
end

nginx_site ngx_conf
