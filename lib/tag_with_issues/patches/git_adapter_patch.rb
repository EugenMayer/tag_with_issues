module TagWithIssues
  module Patches
    module GitAdapterPatch
      def self.included(base)
        base.send(:include, InstanceMethods)
      end

      module InstanceMethods
        def clear_tag_cache
          @tags = nil
        end
      end
    end
  end
end

Redmine::Scm::Adapters::GitAdapter.send(:include, TagWithIssues::Patches::GitAdapterPatch)