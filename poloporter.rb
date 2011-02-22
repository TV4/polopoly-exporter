# classpath needed to run the script, notice that commons-httpclient-3.1.jar need come before jbossall-client.jar
# as the jboss jar include an old httpclient and will nto work with solr

require 'java'
require 'fileutils'
require 'net/http'

include FileUtils

module Polopoly
  require 'yaml'

  CONFIG =  YAML.load_file(File.expand_path("~/.polopoly-exporter/config.yml"))

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
end

def make_policy(cm_server, id)
  if id.match(/^\d+\.\d+/)
    major, minor = id.split '.'
    policy = cm_server.getPolicy(Polopoly::ContentId.new(major.to_i, minor.chomp!.to_i)).to_java(Polopoly::ContentPolicy)
  else
    policy = cm_server.getPolicy(Polopoly::ExternalContentId.new(id)).to_java(Polopoly::ContentPolicy)
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
    "\t\t<component name=\""+ @name + "\" group=\"" + @group + "\">"+ @value +"</component>"
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
  require 'erb'
  
  def initialize(group, name, policy_reference)
    @group = group
    @name = name
    @policy_reference = policy_reference
  end
  def to_s
      "#{@group}\t\t#{@name}\t\t#{@policy_reference}"
  end
  def to_xml
    template = %q{        <contentref group="<%=@group%>" name="<%=@name%>">
            <contentid>
                <externalid><%=@policy_reference%></externalid>
            </contentid>
        </contentref> }
    entry_xml = ERB.new(template, nil, "%<>")
    entry_xml.result binding
  end
  def self.find_content_references(policy)
    refs = []
    policy.content_reference_group_names.each do |group|
      policy.content_reference_names(group).each do |name|
        refs << ContentReference.new(group, name, policy.get_content_reference(group, name))
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
    "#{@path}\t\t#{Polopoly.config['base_content_file_url']}#{@versioned_path}" 
  end
  def to_xml
    "\t\t<file name=" + @path + " encoding=\"URL\">" + Polopoly.config['base_content_file_url'] + @versioned_path + "</file>"
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

module Polopoly
  class Exporter
    attr_accessor :components, :content_references, :content_files
    def initialize
      @components = []
      @content_references = []
      @content_files = []
    end
  end
end

if ARGV.empty? or not ARGV.length == 1
  puts "usage: #{__FILE__} contentid"
else
  client = Polopoly.client 
  cm_server = client.getPolicyCMServer
  policy =  make_policy cm_server, ARGV[0] 
  export = Polopoly::Exporter.new
  export.components = Component.find_components policy
  export.content_references = ContentReference.find_content_references policy
  export.content_files = ContentFile.find_content_files policy
#  export.components.each do |component|
#    puts component.to_xml
#  end
  export.content_references.each do |reference|
    puts reference.to_xml 
  end
#  export.content_files.each do |file|
#    puts file.to_xml
#  end
end
