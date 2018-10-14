id = 'personal-website'

default[id]['fqdn'] = nil
default[id]['ec_certificates'] = true

default[id]['develop'] = false
default[id]['github_repository'] = 'aspyatkin/personal-website'
default[id]['revision'] = 'master'

default[id]['hsts_max_age'] = 15_768_000
default[id]['hpkp_max_age'] = 604_800

default[id]['ruby_version'] = '2.4.1'
default[id]['bundler_version'] = '1.15.4'
