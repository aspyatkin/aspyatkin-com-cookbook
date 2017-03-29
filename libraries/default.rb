require 'etc'

module ChefCookbook
  module AspyatkinCom
    class Helper
      def initialize(node)
        @id = 'aspyatkin-com'
        @node = node
      end

      def instance_user
        @node[@id]['user']
      end

      def instance_group
        ::Etc.getgrgid(::Etc.getpwnam(instance_user).gid).name
      end

      def fqdn
        @node[@id]['fqdn']
      end
    end
  end
end
