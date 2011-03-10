#polopoly-exporter.rb
this is a small script to export a content from a polopoly 9.0 system to 
xml.  this is used to get content from a production or stage environment
to a developement machine.

##usage

    jruby polopoly-exporter.rb [OUTPUT\_DIR] []CONTENT\_ID]

you also need to create ~/.polopoly-exporter/config.yaml to configure
the poloopoly client to connect your polopoly instance.


    polopoly_home: PATH_TO_POLOPOLY_INSTALLATION
    
    jboss_home: PATH_TO_JBOSS_INSTALLATION
    

    #need to split libs into polopoly and jboss as 
    #we use a new version of http-client than what is 
    #in jbossall-client.jar

    polopoly_libs: 
      - /install/lib/servlet.jar
      - /install/lib/polopoly.jar
      - /install/lib/polopoly-community.jar
      - /install/lib/lucene-core-1.9.1.jar
      - /custom/client-lib/PATH_TO_YOUR_SOLOUTION.jar
      - /custom/client-lib/PATH_TO_YOUR_SOLUTION_DEPENDENCIES
    
    jboss_libs:
      - /client/jbossall-client.jar
    
    polopoly_packages:
      - com.polopoly.cm
      - com.polopoly.cm.client
      - com.polopoly.cm.policy
      - com.polopoly.pear
      
    # variables need for using Polopoly::Exporter
    # what environment you are exporting from 
    exporter_config:  
      #used as a prefix to create external id's
      polopoly_env: stage
      #used to create links to file's in content
      base_content_file_url: http://polopoly.example.com/polopoly/polopoly_fs/

## notes

this is tested on polopoly 9.7 series but should work with other versions as well.

to speed up export time try increasing memory used by jruby and use server like so:

    jruby --server -J-Xmx1024m polopoly-exporter.rb [OUTPUT_DIR] [CONTENT_ID]


##example irb

    ➜  polopoly-exporter git:(master) ✗ irb -r polopoly.rb 
    irb(main):001:0> client = Polopoly.client
    => #<Java::ComPolopolyPear::PolopolyApplication:0x519549e>
    irb(main):002:0>  cm_server = client.getPolicyCMServer
    => #<Java::ComPolopolyCmPolicyImpl::PolicyCMServerWrapper:0x4c767fb3>
    irb(main):003:0> sys_dep = Polopoly::Util.find_policy cm_server, 'p.SystemDepartment'
    => #<Java::ComPolopolyCmAppPolicyImpl::SystemConfigPolicy:0x16e7eec9>
    irb(main):004:0> sys_dep.name
    => "System Department"
    irb(main):005:0> quit

##todo
    - make this a gem. as it is handy to fire up irb and require 'polopoly-exporter' to 
            dig around in polopoly.
    - if your sites have refences to other sites this will basically export everything currently
            published.

