require 'etc'

module ChefCookbook
  module AspyatkinCom
    class Helper
      def initialize(node)
        @id = 'aspyatkin-com'
        @node = node
      end

      def root_user
        @node['current_user']
      end

      def instance_user
        ::ENV['SUDO_USER']
      end

      def instance_group
        ::Etc.getgrgid(::Etc.getpwnam(instance_user).gid).name
      end

      def fqdn
        @node[@id]['fqdn'].nil? ? @node['automatic']['fqdn'] : @node[@id]['fqdn']
      end
    end
  end
end
