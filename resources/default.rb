resource_name :personal_website

property :fqdn, String, name_property: true

property :user, String, required: true
property :group, String, required: true

property :develop, [TrueClass, FalseClass], default: false
property :github_repository, String, default: 'aspyatkin/personal-website'
property :revision, String, default: 'master'

property :ruby_version, String, required: true
property :hsts_max_age, Integer, default: 15_768_000

property :listen_ipv6, [TrueClass, FalseClass], default: false
property :default_server, [TrueClass, FalseClass], default: false
property :access_log_options, String, default: 'combined'
property :error_log_options, String, default: 'warn'

default_action :install

action :install do
  secret = ::ChefCookbook::Secret::Helper.new(node)

  repository_url = "https://github.com/#{new_resource.github_repository}"

  if new_resource.develop
    ssh_private_key new_resource.user
    ssh_known_hosts_entry 'github.com'
    repository_url = "git@github.com:#{new_resource.github_repository}.git"
  end

  base_dir = ::File.join('/var/www', new_resource.fqdn)

  directory base_dir do
    owner new_resource.user
    group new_resource.group
    mode 0755
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
    git_config = secret.get('git:config', prefix_fqdn: false, default: {})

    git_config.each do |key, value|
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

  tls_rsa_certificate new_resource.fqdn do
    action :deploy
  end

  tls_helper = ::ChefCookbook::TLS.new(node)
  tls_rsa_item = tls_helper.rsa_certificate_entry(new_resource.fqdn)
  tls_ec_item = nil
  ec_certificates = tls_helper.has_ec_certificate?(new_resource.fqdn)

  if ec_certificates
    tls_ec_certificate new_resource.fqdn do
      action :deploy
    end

    tls_ec_item = tls_helper.ec_certificate_entry(new_resource.fqdn)
  end

  has_scts = tls_rsa_item.has_scts? && (tls_ec_item.nil? ? true : tls_ec_item.has_scts?)

  nginx_vhost_template_vars = {
    fqdn: new_resource.fqdn,
    listen_ipv6: new_resource.listen_ipv6,
    default_server: new_resource.default_server,
    ssl_rsa_certificate: tls_rsa_item.certificate_path,
    ssl_rsa_certificate_key: tls_rsa_item.certificate_private_key_path,
    hsts_max_age: new_resource.hsts_max_age,
    access_log: ::File.join(node['nginx']['log_dir'], "#{new_resource.fqdn}_access.log"),
    access_log_options: new_resource.access_log_options,
    error_log: ::File.join(node['nginx']['log_dir'], "#{new_resource.fqdn}_error.log"),
    error_log_options: new_resource.error_log_options,
    doc_root: ::File.join(base_dir, '_site'),
    oscp_stapling: node.chef_environment.start_with?('production'),
    scts: has_scts,
    scts_rsa_dir: tls_rsa_item.scts_dir,
    ec_certificates: ec_certificates
  }

  if ec_certificates
    nginx_vhost_template_vars.merge!({
      ssl_ec_certificate: tls_ec_item.certificate_path,
      ssl_ec_certificate_key: tls_ec_item.certificate_private_key_path,
      scts_ec_dir: tls_ec_item.scts_dir
    })
  end

  nginx_site new_resource.fqdn do
    cookbook 'personal-website'
    template 'nginx.conf.erb'
    variables nginx_vhost_template_vars
    action :enable
  end
end
