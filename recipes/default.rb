instance = ::ChefCookbook::Instance::Helper.new(node)

node.default['rbenv']['group_users'] = [
  instance.root,
  instance.user
]

include_recipe 'rbenv::default'
include_recipe 'rbenv::ruby_build'

id = 'aspyatkin-com'

repository_url = "https://github.com/#{node[id]['github_repository']}"

if node.chef_environment.start_with? 'development'
  ssh_private_key instance.user
  ssh_known_hosts_entry 'github.com'
  repository_url = "git@github.com:#{node[id]['github_repository']}.git"
end

fqdn = node[id]['fqdn'].nil? ? node['automatic']['fqdn'] : node[id]['fqdn']
base_dir = ::File.join('/var/www', fqdn)

directory base_dir do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

git base_dir do
  repository repository_url
  revision node[id]['revision']
  enable_checkout false
  user instance.user
  group instance.group
  action :sync
end

if node.chef_environment.start_with?('development')
  git_config = secret.get('git:config', prefix_fqdn: false, default: {})

  git_config.each do |key, value|
    git_config key do
      value value
      scope 'local'
      path base_dir
      user instance.user
      action :set
    end
  end
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
  user instance.user
  group instance.group
end

rbenv_execute 'Build website' do
  command 'jekyll build'
  ruby_version node[id]['ruby_version']
  cwd base_dir
  user instance.user
  group instance.group
  environment 'JEKYLL_ENV' => node.chef_environment
end

tls_rsa_certificate fqdn do
  action :deploy
end

tls_rsa_item = ::ChefCookbook::TLS.new(node).rsa_certificate_entry(fqdn)

tls_ec_certificate fqdn do
  action :deploy
end

tls_ec_item = ::ChefCookbook::TLS.new(node).ec_certificate_entry(fqdn)

nginx_site fqdn do
  template 'nginx.conf.erb'
  variables(
    fqdn: fqdn,
    ssl_rsa_certificate: tls_rsa_item.certificate_path,
    ssl_rsa_certificate_key: tls_rsa_item.certificate_private_key_path,
    ssl_ec_certificate: tls_ec_item.certificate_path,
    ssl_ec_certificate_key: tls_ec_item.certificate_private_key_path,
    hsts_max_age: node[id]['hsts_max_age'],
    access_log: ::File.join(node['nginx']['log_dir'], "#{fqdn}_access.log"),
    error_log: ::File.join(node['nginx']['log_dir'], "#{fqdn}_error.log"),
    doc_root: ::File.join(base_dir, '_site'),
    oscp_stapling: node.chef_environment.start_with?('production'),
    scts: node.chef_environment.start_with?('production'),
    scts_rsa_dir: tls_rsa_item.scts_dir,
    scts_ec_dir: tls_ec_item.scts_dir,
    hpkp: node.chef_environment.start_with?('production'),
    hpkp_pins: (tls_rsa_item.hpkp_pins + tls_ec_item.hpkp_pins).uniq,
    hpkp_max_age: node[id]['hpkp_max_age']
  )
  action :enable
end
