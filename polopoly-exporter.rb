require 'fileutils'
require 'polopoly'

include FileUtils
module Polopoly
  class Exporter
    attr_accessor :policy, :major, :external_id, :components, :content_references, :content_files
    def initialize(policy)
      @policy = policy
      @security_parent_util = SecurityParentUtil.new(policy.getCMServer)
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
  include Polopoly
  def initialize(path, versioned_path)
    @path = path 
    @versioned_path = versioned_path.gsub(' ', "%20")
  end
  def to_s
    "#{@path}\t#{Polopoly.config['exporter_config']['base_content_file_url']}#{@versioned_path}" 
  end
  def to_xml
    "        <file name=\"" + @path + "\" encoding=\"URL\">" + Polopoly.config['exporter_config']['base_content_file_url'] + @versioned_path + "</file>\n"
  end
  def self.is_valid_file?(file)
    true unless file.path =~ /(.DS_Store|Thumbs.db)/ or file.is_directory?
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
#taken from http://codeforpeople.com/lib/ruby/alib/alib-0.5.1/lib/alib-0.5.1/util.rb
def snake_case string
  return string unless string =~ %r/[A-Z]/
    string.reverse.scan(%r/[A-Z]+|[^A-Z]*[A-Z]+?/).reverse.map{|word| word.reverse.downcase}.join '_'
end

def camel_case string
  return string if string =~ %r/[A-Z]/ and string !~ %r/_/
    words = string.strip.split %r/\s*_+\s*/
    words.map!{|w| w.downcase.sub(%r/^./){|c| c.upcase}}
  words.join
end

if ARGV.empty? or not ARGV.length == 2
  puts "usage: #{__FILE__} export_dir contentid"
else
  require 'set'
  require 'rexml/document'
  include REXML
  
  export_dir = ARGV[0]
  mkdir_p export_dir
  root_content_id = ARGV[1]
  content_ids_to_export = Set.new
  exported_policies = Set.new
  cm_server = Polopoly.client.getPolicyCMServer
  security_parent_util = Polopoly::SecurityParentUtil.new cm_server
  start_policy =  Polopoly::Util.find_policy cm_server, root_content_id
  content_ids_to_export << start_policy.content_id
  #load the exporter configureation unless it's not cofigured
  export_strategy = Polopoly.config['exporter_config']['export_strategy']
  unless export_strategy.nil?
    require export_strategy
    include export_strategy.camel_case
  else
    module DefaultStrategy
      def export_content?(start_policy, content_id)
        false
      end
    end
    include DefaultStrategy
  end
  content_ids_to_export.each do |content_id|
    puts content_id.to_s
    if security_parent_util.exportable_content?(root_content_id, content_id.content_id.content_id.content_id_string) 
      begin
        policy = Polopoly::Util.find_policy cm_server,"#{content_id.major}.#{content_id.minor}"
        export = Polopoly::Exporter.new policy
        export.components = Component.find_components policy
        export.content_references = ContentReference.find_content_references policy
        export.content_files = ContentFile.find_content_files policy
        File.open(export_dir + "/" + export.external_id + ".xml", "w") do |file|
          file.puts export.to_xml
        end
        exported_policies << content_id
        puts "exported_policies.size = #{exported_policies.size}"
        puts "content_ids_to_export.size = #{content_ids_to_export.size}"
        #do not retrieve under departments.  those can be exported individually
        if export_content?(start_policy, content_id) 
          exportable_ids = export.content_references.collect {|reference| reference.content_reference_id}
          content_ids_to_export.merge exportable_ids
          #remove ids that have already been imported
          content_ids_to_export.reject! {|id| exported_policies.include?(id)}
        end
      rescue
        puts "Exception caught " + $!
      end
    else
      next
    end
  end

  #take all the xml files created in the import and find their
  #externalids and create imports for them.  these need to be imported
  #first.
  
  refs = []
  Dir[export_dir + "/*.xml"].each do |file|
    doc = Document.new(File.new file)
    XPath.each(doc, "//contentref/contentid") do |ref|
      refs <<  [ XPath.first(ref, "./externalid").text, XPath.first(ref, "./major").text ]
    end
  end
  refs.uniq!
  file_number = 1
  mkdir_p "import-first"
  refs.each_slice(500) do |slice|
    File.open("import-first/" + file_number.to_s + ".xml", "w") do |output|
      output.puts %q{<?xml version="1.0" encoding="UTF-8"?>
<batch xmlns="http://www.polopoly.com/polopoly/cm/xmlio" username="sysadmin" password="sysadmin">
      }
      slice.each do |ref|
        output.puts %q{<content><metadata><contentid>}
        output.puts %Q{<major>#{ref[1]}</major>} 
        output.puts %Q{<externalid>#{ref[0]}</externalid>} 
        output.puts %q{</contentid></metadata></content>}
      end
      output.puts %q{</batch>
      }
    end
    file_number = file_number + 1
  end
end
