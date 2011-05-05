module TopDepartmentExportStrategy
  def export_content?(start_policy, content_id)
    start_policy.content_id == content_id || [1,2,13].include?(content_id.major)
  end
end
