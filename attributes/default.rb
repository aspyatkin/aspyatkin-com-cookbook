id = 'aspyatkin-com'

default[id]['user'] = 'vagrant'
default[id]['group'] = 'vagrant'
default[id]['fqdn'] = 'aspyatkin.dev'

default[id]['repository'] = 'https://github.com/aspyatkin/aspyatkin.com'
default[id]['revision'] = 'master'

default[id]['hsts_max_age'] = 15_768_000
default[id]['hpkp_max_age'] = 604_800

default[id]['ruby_version'] = '2.3.0'
