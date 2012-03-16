class TagsCustomFieldFormat < Redmine::CustomFieldFormat
  include ActionView::Helpers::TagHelper

  def format_as_tags(value)
    # It would be nicer to get the field we are currently working on, but this doesn't seem possible
    begin
      tag_field_name = Setting.plugin_tag_with_issues['tag_field_name']
      tag_field = CustomField.find(:first, :conditions => ["name=?", tag_field_name])
      raise ActiveRecord::RecordNotFound if tag_field.nil?
    rescue ActiveRecord::RecordNotFound
      return value
    end

    tags = value.split(",")
    tag_links = tags.map do |tag|
      tag = h(tag.strip)
      "<a href=\"/issues?set_filter=1&f[]=cf_#{tag_field.id}&op[cf_#{tag_field.id}]=~&v[cf_#{tag_field.id}][]=#{tag}\">#{tag}</a>"
    end
    ActiveSupport::SafeBuffer.new(tag_links.join(", "))
  end

  def escape_html?
    false
  end

  def edit_as
    "string"
  end
end

Redmine::CustomFieldFormat.map do |fields|
  fields.register TagsCustomFieldFormat.new('tags', :label => :label_tags, :order => 9)
end