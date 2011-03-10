# classpath needed to run the script, notice that commons-httpclient-3.1.jar need come before jbossall-client.jar
# as the jboss jar include an old httpclient and will nto work with solr

require 'java'
module Polopoly
  require 'yaml'

  CONFIG =  YAML.load_file(File.expand_path("~/.polopoly-jruby/config.yaml"))

  def self.client
    #read out properties.
    java.lang.System.setProperty("java.util.logging.config.file", File.expand_path("~/.polopoly-jruby/logging.properties"))
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
  class Util
    def self.find_major_name(policy)
      (policy.getCMServer.major_info policy.content_id.content_id.major).name
    end
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
        policy = cm_server.getPolicy(Polopoly::ContentId.new(major.to_i, minor.to_i)).to_java(Polopoly::ContentPolicy)
      else
        policy = cm_server.getPolicy(Polopoly::ExternalContentId.new(id)).to_java(Polopoly::ContentPolicy)
      end
    end    
  end    
  class SecurityParentUtil
    def initialize(cm_server)
      @cm_server = cm_server
    end
    def find_security_parents(child)
      content_ids = [child.content_id.content_id.content_id_string]
      current_content = find_security_parent(child)
      until current_content.nil?
        content_ids << current_content.content_id.content_id.content_id_string 
        current_content =  find_security_parent(current_content)
      end
      content_ids
    end
    def find_security_parent(content)
      unless content.security_parent_id.nil? 
        @cm_server.get_content(content.security_parent_id) 
      end
    end
    #root_content_id is the highest node in that we are interested in
    #content_id should be a leaf node of root_content_id
    def exportable_content?(root_content_id, content_id)
      begin
        branch = find_security_parents(Polopoly::Util.find_policy(@cm_server, content_id))
        branch.include?(Polopoly::Util.find_policy(@cm_server, root_content_id).content_id.content_id.content_id_string)
      rescue
        #return true on error to get the referred content.
        true
      end
    end
  end
end

