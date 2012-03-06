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
          @repository.fetch_changesets if Setting.autofetch_changesets?
          @has_branches = (!@repository.branches.nil? && @repository.branches.length > 0)
          branches = @has_branches ? @repository.branches : [@repository.default_branch]
          @changesets_by_branch = branches.inject({}) { |h,b| h[b] = @repository.latest_changesets("", b); h }

          @tags = @repository.tags.collect do |tag|
            # changeset = @repository.find_changeset_by_name(tag)
            changeset = @repository.latest_changesets("", tag).first
            tag_info = {:name => tag, :id => "?", :commit_message => "<no commit message>"}
            unless changeset.nil?
              tag_info[:id] = changeset.format_identifier
              tag_info[:commit_message] = changeset.comments
            end
            tag_info
          end
        end
        
        def create_tag
          success = false

          if success
            flash[:notice] = l(:notice_successfully_created_tag)
          else
            flash[:error] = l(:error_creating_tag)
          end
          redirect_to :controller => 'projects', :action => 'show', :id => @project.id
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