require 'fileutils'
require 'polopoly'

include FileUtils

if ARGV.empty? or not ARGV.length == 1
  puts "usage: #{__FILE__} import_dir"
else
  import_dir = ARGV[0]
  start = Time.now
  begin
    cm_server = Polopoly.client.getPolicyCMServer
    importer = Polopoly::DocumentImporterFactory.getDocumentImporter(cm_server)
    Dir[import_dir + "*/*.xml"].each_slice(10) do |slice|
      slice.each do |file|
        begin
          importer.importXML(java.io.File.new(file))
        rescue
          puts $!
        end
      end
      print "."
    end
    puts
  rescue
    puts "Exception caught " + $!
  end
  puts "finished in #{Time.now  - start} seconds"
end
