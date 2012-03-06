module TagWithIssues
  module Patches
    module IssuesControllerPatch
      def self.included(base)
        base.send(:include, InstanceMethods)

        base.class_eval do
          unloadable
          # add the tag action to the before_filter methods that trigger find_issues
          # otherwise the @issues variable is not generated from the ids in params.
          # In particular @project will not be set, causing authorize to fail
          base.filter_chain.detect{|filter| filter.method == :find_issues}.options[:only] << "tag" << "create_tag"
          
          before_filter :check_unique_project, :only => [:tag, :create_tag]
          before_filter :find_repository, :only => [:tag, :create_tag]
        end
      end

      module InstanceMethods
        def tag
          @issues.sort!
          @major_version = Setting.plugin_tag_with_issues['major_version']
          has_branches = (!@repository.branches.nil? && @repository.branches.length > 0)
        end
        
        def create_tag
        end
        
        private

        def check_unique_project
          unless @project
            render_error 'Tagging a commit with issues from other projects is not supported'
            return false
          end
        end
        
        def find_repository
          @repository = @project.repository
          (render_404; return false) unless @repository
        rescue ActiveRecord::RecordNotFound
          render_404
        end
      end
    end
  end    
end

IssuesController.send(:include, TagWithIssues::Patches::IssuesControllerPatch)