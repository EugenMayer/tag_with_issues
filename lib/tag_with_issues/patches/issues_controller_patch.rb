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
          before_filter :find_tag_name, :only => [:create_tag]
          before_filter :validate_tag_name, :only => [:create_tag]
          before_filter :find_commit, :only => [:create_tag]
        end
      end

      module InstanceMethods
        def tag
          @issues.sort!
          @tag_name_major_version = Setting.plugin_tag_with_issues['major_version']
          @can_edit_major_version = @tag_name_major_version.empty?
          @tag_name_minor_version, @tag_name_internal_version_extra, @tag_name_custom = "", "", ""
          @repository.fetch_changesets if Setting.autofetch_changesets?
          @has_branches = (!@repository.branches.nil? && @repository.branches.length > 0)
          branches = @has_branches ? @repository.branches : [@repository.default_branch]
          @changesets_by_branch = branches.inject({}) { |h,b| h[b] = @repository.latest_changesets("", b); h }
          @tagged_changesets = []

          @tags = @repository.tags.collect do |tag|
            changeset = @repository.latest_changesets("", tag).first
            @tagged_changesets << changeset
            tag_info = {:name => tag, :id => "?", :commit_message => "<no commit message>"}
            unless changeset.nil?
              tag_info[:id] = changeset.format_identifier
              tag_info[:commit_message] = changeset.comments
              tag_info[:committed_on] = changeset.committed_on
            end
            tag_info
          end
          @tags = @tags.sort_by { |t| t[:committed_on]}.reverse

          unless @tags.empty?
            latest_tag_name = @tags[0][:name]
            if latest_tag_name =~ /\A([^-]*)-([^-]*)(-(.*))?\Z/
              @tag_name_minor_version, @tag_name_internal_version_extra = $2, $4
              if @can_edit_major_version
                @tag_name_major_version = $1
              end
            else
              @tag_name_custom = latest_tag_name
            end
          end

          @youngest_changeset = nil
          @youngest_changeset_branch = nil
          @changesets_by_branch.each do |branch, changesets|
            # order commits: first show untagged commits then tagged commits. Each list ordered by descending commit date
            changesets.sort! do |a,b|
              if (@tagged_changesets.include? a) == (@tagged_changesets.include? b)
                b.committed_on <=> a.committed_on or
                a.format_identifier <=> b.format_identifier
              elsif @tagged_changesets.include? a
                1
              else
                -1
              end
            end
            # insert dummy option to separate tagged and untagged commits
            first_tagged_index = changesets.index {|c| @tagged_changesets.include? c}
            changesets.insert(first_tagged_index, nil) unless first_tagged_index.nil? or first_tagged_index == 0
            # select youngest untagged commit as default
            unless changesets.empty?

              if @youngest_changeset.nil? or
                   ((@tagged_changesets.include? @youngest_changeset) and (!@tagged_changesets.include? changesets[0])) or
                   ((@tagged_changesets.include? @youngest_changeset) == (!@tagged_changesets.include? changesets[0]) and
                       @youngest_changeset.committed_on < changesets[0].committed_on)
                @youngest_changeset = changesets[0]
                @youngest_changeset_branch = branch
              end
            end
          end

        end
        
        def create_tag
          tag_command = Setting.plugin_tag_with_issues['git_tag_command']
          if tag_command.nil? or tag_command.empty?
            render_error "Please configure the tag command in the plugin's config first"
            return false
          end

          tag_command = tag_command.gsub(/<commit_id>/, Redmine::Scm::Adapters::AbstractAdapter::shell_quote(@commit_id))
          tag_command = tag_command.gsub(/<tag_name>/, Redmine::Scm::Adapters::AbstractAdapter::shell_quote(@tag_name))
          tag_command = tag_command.gsub(/<repository_path>/, @repository.url)
          logger.debug "Executing git tag command '#{tag_command}'"
          success = system(tag_command)
          logger.debug "Return value '#{$?}'"

          if success
            clear_tag_cache
            # tagging was successful now try to add the new tag to the issues custom tags field
            begin
              tag_field_name = Setting.plugin_tag_with_issues['tag_field_name']
              raise ActiveRecord::RecordNotFound if tag_field_name.nil? or tag_field_name.empty?
              tag_field = CustomField.find(:first, :conditions => ["name=?", tag_field_name])
              raise ActiveRecord::RecordNotFound if tag_field.nil?
            rescue ActiveRecord::RecordNotFound
              flash[:error] = l(:error_could_not_find_tag_field)
              return
            end
            failed_issues = []

            errors = []
            @issues.each do |issue|
              # TODO is there an easier way to do this?
              custom_field_hash = issue.custom_field_values.inject({}) { |h, v| h[v.custom_field_id] = v.value; h }
              tags = custom_field_hash[tag_field.id]
              if tags.nil? or tags.empty?
                custom_field_hash[tag_field.id] = "[#{@tag_name}]"
              else
                custom_field_hash[tag_field.id] = "#{tags},[#{@tag_name}]"
              end
              issue.custom_field_values = custom_field_hash
              tag_field_updated = issue.save
              failed_issues << issue unless tag_field_updated
              logger.debug "Calling hook controller_issues_tag_after_save"
              hook_context = { :params => params, :issue => issue, :tag_field_updated => tag_field_updated,
                               :hook_response => {:success => true, :error_message => ""} }
              call_hook(:controller_issues_tag_after_save, hook_context)
              logger.debug "Hook controller_issues_tag_after_save returned " + hook_context[:hook_response][:success].to_s
              unless hook_context[:hook_response][:success]
                  errors << "#{l(:error_in_hook)} (#{issue.id}): #{hook_context[:hook_response][:error_message]}"
              end
            end

            if failed_issues.any?
              errors.insert(0, l(:error_adding_tag_to_custom_field + ' ' + failed_issues.collect { |i| i.id }.join(', ')))
            end
            if errors.empty?
              flash[:notice] = l(:notice_successfully_created_tag)
            else
              flash[:error] = errors.join("<br>")
            end
          else
            flash[:error] = l(:error_creating_tag) + " (Tag: '#{@tag_name}' commit: '#{@commit.identifier}' Repo:'#{@repository.url}')"
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

        def find_tag_name
          @tag_name = params[:tag_name_custom]
          return true unless @tag_name.empty?

          if params[:tag_name_major_version].empty? or params[:tag_name_minor_version].empty?
            render_error(:message => l(:error_tag_name_insufficient),
                          :status => 500)
            return false
          end

          # TODO Format should be configurable
          @tag_name = "#{params[:tag_name_major_version]}-#{params[:tag_name_minor_version]}"
          unless params[:tag_name_internal_version_extra].empty?
            @tag_name += "-#{params[:tag_name_internal_version_extra]}"
          end

          if @repository.tags.include? @tag_name
            render_error(:message => l(:error_tag_name_already_in_use),
                         :status => 500)
            return false
          end
        end

        def validate_tag_name
          tag_validate_regexp = Setting.plugin_tag_with_issues['tag_validate_regexp']
          return true if tag_validate_regexp.nil? or tag_validate_regexp.empty?
          unless @tag_name =~ /#{tag_validate_regexp}/
            render_error(:message => "#{l(:error_tag_name_validation)} (tag name: '#{@tag_name}')",
                         :status => 500)
            return false
          end
        rescue RegexpError => exc
          render_error(:message => "#{l(:error_invalid_regexp)}: '#{exc.message}'",
                       :status => 500)
          return false
        end

        def find_commit
          @commit_id = params[:commit_id]
          raise ActiveRecord::RecordNotFound if @commit_id.empty?
          @commit = @repository.find_changeset_by_name(@commit_id)
        rescue ActiveRecord::RecordNotFound
          render_404
        end

        def clear_tag_cache
          if @repository.scm.respond_to?(:clear_tag_cache)
            @repository.scm.clear_tag_cache
            logger.debug "Cleared tag cache of SCM adapter"
          end

          # special case for redmine_git_hosting plugin
          if defined?(GitHosting) == 'constant' and GitHosting.class == Module and GitHosting.respond_to?(:clear_cache_for_project)
              GitHosting.clear_cache_for_project(@project)
          end
        end

      end
    end
  end    
end

IssuesController.send(:include, TagWithIssues::Patches::IssuesControllerPatch)