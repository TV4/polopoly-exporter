class TopDepartmentExportStrategy
  def self.export_content?(start_policy, content_id)
    start_policy.content_id == content_id || content_id.major == 1 || content_id.major == 13
  end
end
