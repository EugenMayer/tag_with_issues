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
        'git_tag_command' => 'git --git-dir=<repository_path> tag <tag_name> <commit_id>',
        # use with gitolite and custom tagrepo script
        # sudo -i -u gitolite sh -c '/usr/local/bin/tagrepo ~/<repository_path> <tag_name> <commit_id>'
        'tag_field_name' => 'Tags',
      }
end

require 'dispatcher'
Dispatcher.to_prepare :tag_with_issues do
  require_dependency 'tag_with_issues/patches/issues_controller_patch'
end

require 'tag_with_issues/hooks/view_issues_context_menu_hook'

require 'tag_with_issues/custom_field_format/tag_custom_field_format'
