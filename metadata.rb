name 'personal-website'
description 'Installs and configures personal website'
version '1.15.0'

recipe 'personal-website', 'Installs and configures personal website'
depends 'git'
depends 'nodejs'
depends 'nginx'
depends 'ruby_rbenv', '~> 2.1.0'
depends 'ssh_known_hosts', '~> 4.0.0'
depends 'ssh-private-keys', '~> 2.0.0'
depends 'tls', '~> 3.0.4'
depends 'instance', '~> 2.0.1'
depends 'secret', '~> 1.0.0'
