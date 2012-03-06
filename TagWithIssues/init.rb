require 'redmine'

Redmine::Plugin.register :tag_with_issues do
  name 'TagWithIssues plugin'
  author 'Florian Pommerening'
  description 'Allows to select '
  version '0.0.1'
  url 'https://bugtracking.kontextwork.de/issues/676'
  project_module :tag_with_issues do
    permission :tag_with_issues, {:issues => [:tag, :create_tag]}, :require => :member
  end
  settings :partial => 'settings/tag_with_issues',
    :default => {
        # TODO: this should be a project-wide setting not a global setting
        'major_version' => '1',
      }
end

require 'dispatcher'
Dispatcher.to_prepare :tag_with_issues do
  require_dependency 'tag_with_issues/patches/issues_controller_patch'
end

require 'tag_with_issues/hooks/view_issues_context_menu_hook'
