# classpath needed to run the script, notice that commons-httpclient-3.1.jar need come before jbossall-client.jar
# as the jboss jar include an old httpclient and will nto work with solr

require 'java'
require 'fileutils'
include FileUtils
module Polopoly
  require 'yaml'

  CONFIG =  YAML.load_file(File.expand_path("~/.polopoly-exporter/config.yaml"))

  def self.client
    CONFIG["polopoly_libs"].each do |lib|
      require CONFIG["polopoly_home"] + lib
    end

    CONFIG["jboss_libs"].each do |lib|
      require CONFIG["jboss_home"] + lib
    end

    CONFIG["polopoly_packages"].each do |package|
      include_package package
    end
    ApplicationFactory.create_application([CONFIG["polopoly_home"]+ "/pear/config/polopolyclient.properties"].to_java(:string))
  end
  def self.config
    CONFIG
  end
  class Exporter
    attr_accessor :external_id, :components, :content_references, :content_files
    def initialize(external_id)
      @external_id = external_id
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
  end
  class Util
    def self.make_external_id(policy)
      unless policy.external_id.nil?
        external_id = policy.external_id.external_id
      else
        external_id = Polopoly.config['exporter_config']['polopoly_env'] + "-" + policy.content_id.major.to_s + "." + policy.content_id.minor.to_s
      end
    end
    def self.find_policy(cm_server, id)
      if id.match(/^\d+\.\d+/)
        major, minor = id.split '.'
        #policy = cm_server.getPolicy(Polopoly::ContentId.new(major.to_i, minor.chomp!.to_i)).to_java(Polopoly::ContentPolicy)
        policy = cm_server.getPolicy(Polopoly::ContentId.new(major.to_i, minor.to_i)).to_java(Polopoly::ContentPolicy)
      else
        policy = cm_server.getPolicy(Polopoly::ExternalContentId.new(id)).to_java(Polopoly::ContentPolicy)
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
    "        <component name=\""+ @name + "\" group=\"" + @group + "\">"+ @value +"</component>\n"
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
  attr_accessor :content_reference_id, :group, :name, :external_id
  def initialize(group, name, content_reference_id, external_id)
    @group = group
    @name = name
    @content_reference_id= content_reference_id
    @external_id = external_id
  end
  def to_s
      "#{@group}\t#{@name}\t\t#{@external_id}"
  end
  def to_xml
    %Q{        <contentref group="#{@group}" name="#{@name}">
            <contentid>
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
        external_id = Polopoly::Util.make_external_id(policy.getCMServer.get_policy(policy.get_content_reference(group, name)))
        refs << ContentReference.new(group, name, content_reference_id, external_id)
      end
    end
    refs
  end
end

class ContentFile
  include Polopoly
  def initialize(path, versioned_path)
    @path = path 
    @versioned_path = versioned_path
  end
  def to_s
    "#{@path}\t#{Polopoly.config['exporter_config']['base_content_file_url']}#{@versioned_path}" 
  end
  def to_xml
    "        <file name=\"" + @path + "\" encoding=\"URL\">" + Polopoly.config['exporter_config']['base_content_file_url'] + @versioned_path + "</file>\n"
  end
  def self.is_valid_file?(file)
    true unless file.path =~ /(.*_gen.*|.DS_Store|Thumbs.db)/ or file.is_directory?
  end
  def self.find_content_files(policy)
    files = []
    policy.listFiles('/', true).each do |file|
      if is_valid_file?(file)
        files << ContentFile.new(file.path, "#{policy.content_id.major}.#{policy.content_id.minor}.#{policy.content_id.version}!#{file.path}")
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
    begin
      policy = Polopoly::Util.find_policy cm_server,"#{content_id.major}.#{content_id.minor}"
    export = Polopoly::Exporter.new Polopoly::Util.make_external_id policy
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
