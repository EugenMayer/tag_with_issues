module TagWithIssues
  module Hooks
    class ViewIssuesContextMenuHook < Redmine::Hook::ViewListener
      render_on :view_issues_context_menu_end,
                :partial => 'hooks/view_issues_context_menu_end'
    end
  end
end