name 'aspyatkin-com'
description 'Installs and configures aspyatkin.com'
version '1.7.1'

recipe 'aspyatkin-com', 'Installs and configures aspyatkin.com'
depends 'git', '~> 6.1.0'
depends 'latest-nodejs', '~> 1.4.0'
depends 'chef_nginx', '~> 6.1.1'
depends 'rbenv', '~> 1.7.1'
depends 'ssh_known_hosts', '~> 4.0.0'
depends 'ssh-private-keys', '~> 2.0.0'
depends 'tls', '~> 3.0.0'

