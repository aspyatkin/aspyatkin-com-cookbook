instance = ::ChefCookbook::Instance::Helper.new(node)
secret = ::ChefCookbook::Secret::Helper.new(node)

rbenv_user_install instance.user

rbenv_plugin 'ruby-build' do
  git_url 'https://github.com/rbenv/ruby-build.git'
  user instance.user
end

id = 'personal-website'

repository_url = "https://github.com/#{node[id]['github_repository']}"

if node[id]['develop']
  ssh_private_key instance.user
  ssh_known_hosts_entry 'github.com'
  repository_url = "git@github.com:#{node[id]['github_repository']}.git"
end

fqdn = node[id]['fqdn'].nil? ? node['fqdn'] : node[id]['fqdn']
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

if node[id]['develop']
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
  user instance.user
end

rbenv_global node[id]['ruby_version'] do
  user instance.user
end

rbenv_gem 'bundler' do
  user instance.user
  rbenv_version node[id]['ruby_version']
  version node[id]['bundler_version']
end

execute 'Fix permissions on bundle cache dir' do
  command "chown -R #{instance.user}:#{instance.group} #{instance.user_home}/.bundle"
  action :run
end

rbenv_script "Install bundle at #{base_dir}" do
  code 'bundle'
  rbenv_version node[id]['ruby_version']
  cwd base_dir
  user instance.user
  group instance.group
end

rbenv_script 'Build website' do
  code 'jekyll build'
  rbenv_version node[id]['ruby_version']
  cwd base_dir
  user instance.user
  group instance.group
  environment 'JEKYLL_ENV' => node.chef_environment
end

tls_rsa_certificate fqdn do
  action :deploy
end

tls_rsa_item = ::ChefCookbook::TLS.new(node).rsa_certificate_entry(fqdn)
tls_ec_item = nil

if node[id]['ec_certificates']
  tls_ec_certificate fqdn do
    action :deploy
  end

  tls_ec_item = ::ChefCookbook::TLS.new(node).ec_certificate_entry(fqdn)
end

has_scts = tls_rsa_item.has_scts? && (tls_ec_item.nil? ? true : tls_ec_item.has_scts?)

nginx_vhost_template_vars = {
  fqdn: fqdn,
  ssl_rsa_certificate: tls_rsa_item.certificate_path,
  ssl_rsa_certificate_key: tls_rsa_item.certificate_private_key_path,
  hsts_max_age: node[id]['hsts_max_age'],
  access_log: ::File.join(node['nginx']['log_dir'], "#{fqdn}_access.log"),
  access_log_options: node['nginx']['log_formats'].has_key?('main_ext') ? 'main_ext' : 'combined',
  error_log: ::File.join(node['nginx']['log_dir'], "#{fqdn}_error.log"),
  error_log_options: 'warn',
  doc_root: ::File.join(base_dir, '_site'),
  oscp_stapling: node.chef_environment.start_with?('production'),
  scts: has_scts,
  scts_rsa_dir: tls_rsa_item.scts_dir,
  hpkp: node.chef_environment.start_with?('production'),
  hpkp_pins: tls_rsa_item.hpkp_pins,
  hpkp_max_age: node[id]['hpkp_max_age'],
  ec_certificates: node[id]['ec_certificates']
}

if node[id]['ec_certificates']
  nginx_vhost_template_vars.merge!({
    ssl_ec_certificate: tls_ec_item.certificate_path,
    ssl_ec_certificate_key: tls_ec_item.certificate_private_key_path,
    scts_ec_dir: tls_ec_item.scts_dir,
    hpkp_pins: (nginx_vhost_template_vars[:hpkp_pins] + tls_ec_item.hpkp_pins).uniq
  })
end

nginx_site fqdn do
  template 'nginx.conf.erb'
  variables nginx_vhost_template_vars
  action :enable
end
