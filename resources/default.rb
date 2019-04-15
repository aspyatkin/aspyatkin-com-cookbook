resource_name :personal_website

property :fqdn, String, name_property: true

property :user, String, required: true
property :group, String, required: true

property :develop, [TrueClass, FalseClass], default: false
property :git_config, Hash, default: {}
property :github_repository, String, default: 'aspyatkin/personal-website'
property :revision, String, default: 'master'

property :ruby_version, String, required: true
property :hsts_max_age, Integer, default: 15_768_000
property :oscp_stapling, [TrueClass, FalseClass], default: true
property :resolvers, Array, default: %w(8.8.8.8 1.1.1.1 8.8.4.4 1.0.0.1)
property :resolver_valid, Integer, default: 600
property :resolver_timeout, Integer, default: 10

property :listen_ipv6, [TrueClass, FalseClass], default: false
property :default_server, [TrueClass, FalseClass], default: false
property :access_log_options, String, default: 'combined'
property :error_log_options, String, default: 'warn'

default_action :install

action :install do
  repository_url = "https://github.com/#{new_resource.github_repository}"

  if new_resource.develop
    ssh_known_hosts_entry 'github.com'
    repository_url = "git@github.com:#{new_resource.github_repository}.git"
  end

  base_dir = ::File.join('/var/www', new_resource.fqdn)

  directory base_dir do
    owner new_resource.user
    group new_resource.group
    mode 0o755
    recursive true
    action :create
  end

  git base_dir do
    repository repository_url
    revision new_resource.revision
    enable_checkout false
    user new_resource.user
    group new_resource.group
    action :sync
  end

  if new_resource.develop
    new_resource.git_config.each do |key, value|
      git_config key do
        value value
        scope 'local'
        path base_dir
        user new_resource.user
        action :set
      end
    end
  end

  rbenv_script "Install bundle at #{base_dir}" do
    code 'bundle'
    rbenv_version new_resource.ruby_version
    cwd base_dir
    user new_resource.user
    group new_resource.group
  end

  rbenv_script 'Build website' do
    code 'jekyll build'
    rbenv_version new_resource.ruby_version
    cwd base_dir
    user new_resource.user
    group new_resource.group
    environment 'JEKYLL_ENV' => node.chef_environment
  end

  vhost_vars = {
    fqdn: new_resource.fqdn,
    listen_ipv6: new_resource.listen_ipv6,
    default_server: new_resource.default_server,
    access_log_options: new_resource.access_log_options,
    error_log_options: new_resource.error_log_options,
    doc_root: ::File.join(base_dir, '_site'),
    hsts_max_age: new_resource.hsts_max_age,
    oscp_stapling: new_resource.oscp_stapling,
    resolvers: new_resource.resolvers,
    resolver_valid: new_resource.resolver_valid,
    resolver_timeout: new_resource.resolver_timeout,
    certificate_entries: []
  }

  tls_rsa_certificate new_resource.fqdn do
    action :deploy
  end

  tls = ::ChefCookbook::TLS.new(node)
  vhost_vars[:certificate_entries] << tls.rsa_certificate_entry(new_resource.fqdn)

  if tls.has_ec_certificate?(new_resource.fqdn)
    tls_ec_certificate new_resource.fqdn do
      action :deploy
    end

    vhost_vars[:certificate_entries] << tls.ec_certificate_entry(new_resource.fqdn)
  end

  nginx_vhost new_resource.fqdn do
    cookbook 'personal-website'
    template 'nginx.conf.erb'
    variables(lazy {
      vhost_vars.merge(
        access_log: ::File.join(node.run_state['nginx']['log_dir'], "#{new_resource.fqdn}_access.log"),
        error_log: ::File.join(node.run_state['nginx']['log_dir'], "#{new_resource.fqdn}_error.log")
      )
    })
    action :enable
  end
end
