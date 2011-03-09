require 'fileutils'
require 'polopoly'

include FileUtils
module Polopoly
  class Exporter
    attr_accessor :policy, :major, :external_id, :components, :content_references, :content_files
    def initialize(policy)
      @policy = policy
      @major =  Polopoly::Util.find_major_name policy
      @external_id = Polopoly::Util.make_external_id policy
      @components = []
      @content_references = []
      @content_files = []
    end
    def to_xml
      xml =  %Q{<?xml version="1.0" encoding="UTF-8"?>
<batch xmlns="http://www.polopoly.com/polopoly/cm/xmlio" username="sysadmin" password="sysadmin">
     <content>
          <metadata>
              <contentid>
                  <major>#{@major}</major>
                  <externalid>#{@external_id}</externalid>
              </contentid>
          </metadata>
  }
      @components.each do |component|
        xml <<  component.to_xml
      end
      @content_references.each do |reference|
        xml <<  reference.to_xml 
      end
      @content_files.each do |file|
        xml <<  file.to_xml
      end
      xml <<  %q{
     </content>
</batch>
}    
    end
    def self.exportable_content?(content_id)
      #article, department, reference metadata
      exportable_majors = [1, 2, 13]
      unless (content_id.major != 2 && content_id.minor != 2) && exportable_majors.include?(content_id.major)
        true
      else
        false
      end
    end
  end
end


class Component
  def initialize(group, name, value)
    @group = group
    @name = name
    @value = value
  end
  def to_s
      "#{@group}\t\t#{@name}\t\t#{@value}"
  end
  def to_xml
    "        <component name=\""+ @name + "\" group=\"" + @group + "\"><![CDATA["+ @value +"]]></component>\n"
  end
  def self.find_components(policy)
    components = []
    policy.component_group_names.each do |group|
      policy.component_names(group).each do |name|
        components << Component.new(group, name, policy.get_component(group, name))
      end
    end
    components
  end
end

class ContentReference 
  attr_accessor :major, :content_reference_id, :group, :name, :external_id
  def initialize(group, name, content_reference_id, policy)
    @major = Polopoly::Util.find_major_name policy
    @group = group
    @name = name
    @content_reference_id = content_reference_id
    #@external_id =  Polopoly::Util.make_external_id(policy.getCMServer.get_policy(policy.get_content_reference(group, name)))
    @external_id =  Polopoly::Util.make_external_id(policy)
  end
  def to_s
      "#{@group}\t#{@name}\t\t#{@external_id}"
  end
  def to_xml
    %Q{        <contentref group="#{@group}" name="#{@name}">
            <contentid>
                <major>#{@major}</major>
                <externalid>#{@external_id}</externalid>
            </contentid>
        </contentref> 
}
  end
  def self.find_content_references(policy)
    refs = []
    policy.content_reference_group_names.each do |group|
      policy.content_reference_names(group).each do |name|
        content_reference_id = policy.get_content_reference(group, name)
        content_reference_policy = policy.getCMServer.get_policy(policy.get_content_reference(group, name))
        refs << ContentReference.new(group, name, content_reference_id, content_reference_policy)
      end
    end
    refs
  end
end

class ContentFile
  $KCODE = "u" #Use UTF-8 ruby 1.8 affects cgi.escape
  require 'cgi'
  include Polopoly
  def initialize(path, versioned_path)
    @path = path 
    @versioned_path = versioned_path
  end
  def to_s
    "#{@path}\t#{Polopoly.config['exporter_config']['base_content_file_url']}#{@versioned_path}" 
  end
  def to_xml
    "        <file name=\"" + @path + "\" encoding=\"URL\">" + Polopoly.config['exporter_config']['base_content_file_url'] + CGI.escape(@versioned_path) + "</file>\n"
  end
  def self.is_valid_file?(file)
    true unless file.path =~ /(.*_gen.*|.DS_Store|Thumbs.db)/ or file.is_directory?
  end
  def self.find_content_files(policy)
    files = []
    policy.listFiles('/', true).each do |file|
      if is_valid_file?(file)
        files << ContentFile.new(file.path, "#{policy.content_id.major}.#{policy.content_id.minor}!#{file.path}")
      end
    end
    files
  end
end
if ARGV.empty? or not ARGV.length == 2
  puts "usage: #{__FILE__} export_dir contentid"
else
  require 'set'
  mkdir_p ARGV[0]
  content_ids_to_export = Set.new
  exported_policies = Set.new
  cm_server = Polopoly.client.getPolicyCMServer
  start_policy =  Polopoly::Util.find_policy cm_server, ARGV[1] 
  puts start_policy.content_id.to_s
  content_ids_to_export << start_policy.content_id
  content_ids_to_export.each do |content_id|
    unless Polopoly::Exporter.exportable_content?(content_id) 
      break
    else
      begin
        policy = Polopoly::Util.find_policy cm_server,"#{content_id.major}.#{content_id.minor}"
        export = Polopoly::Exporter.new policy
        export.components = Component.find_components policy
        export.content_references = ContentReference.find_content_references policy
        export.content_files = ContentFile.find_content_files policy
        File.open(ARGV[0] + "/" + export.external_id + ".xml", "w") do |file|
          file.puts export.to_xml
        end
        exported_policies << content_id
        puts "exported_policies.size = #{exported_policies.size}"
        exportable_ids = export.content_references.collect {|reference| reference.content_reference_id}
        content_ids_to_export.merge exportable_ids
        #remove ids that have already been imported
        content_ids_to_export.reject! {|id| exported_policies.include?(id)}
      rescue
        puts "Exception caught " + $!
      end
    end
  end
end
