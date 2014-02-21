require 'uri'
require 'net/http'
require 'net/https'
require 'active_support/inflector'
require 'json'
require 'yaml'

def add_to_muninn node_type, json_object
    config = YAML.load_file("config.yml")

    node_type_plural = node_type.pluralize
  	uri_string = "/#{node_type_plural}/"
    http = Net::HTTP.new(config["muninn_host"], config["muninn_port"])
    http.use_ssl = config["muninn_uses_ssl"]
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE #Muninn is using a self-signed cert

    request = Net::HTTP::Post.new("#{uri_string}", initheader = {'Content-Type' =>'application/json'})
    request.body = json_object

    return http.request(request)
end

def extract_file(file_name)
  source_file = File.open(file_name, "r")
  json_objects = []
  current_string = nil
  current_type = nil
  source_file.each_line do |line|
    line.strip!
    if line != nil && line != ""
      if line == "#END"
        json_objects << { :type => current_type, :json => current_string }
        puts "*** Added.\n"
        current_type = nil
        current_string = nil
      elsif line[0] == "#"
        current_string = ""
        current_type = line[1,line.length-1].downcase
        puts "*** Adding: " + current_type
      else
        if current_type == nil
          puts "*** Missing #TYPE declaration at beginning of object."
          return nil
        end
        if current_string == nil
          current_string = line
        else
          current_string = current_string + line
        end
        #puts line
      end
    end
  end
  source_file.close
  if current_string != nil
    puts "*** Missing #END at end of final object in file #{file_name}."
    return nil
  end
  return json_objects
end

def load_objects json_objects
  number_loaded = 1
  error_objects = []
  while number_loaded > 0 do
    number_loaded = 0
    error_objects = []
    json_objects.each do |json_object|
      result = add_to_muninn(json_object[:type], json_object[:json])
      result_json = JSON.parse(result.body)
      if result_json["Success"]
        number_loaded = number_loaded + 1
      else
        error_objects << {
          :type => json_object[:type],
          :json => json_object[:json],
          :message => result_json["Message"]
        }
      end
    end
    json_objects = error_objects
  end
  if error_objects.length > 0
    error_objects.each do |error_object|
      puts "*** Error loading " + error_object[:type] + ": " + error_object[:message] +
      "\nCaused by:\n\n" +
      error_object[:json] +
      "\n\n"
    end
  else
    puts "*** All objects loaded successfully."
  end
end

Dir.glob("Data/*.txt") do |file_name|
  puts "\n*** Extracting JSON objects from #{file_name}..."
  json_objects = extract_file(file_name)
  puts "\n*** Loading to Muninn..."
  load_objects(json_objects)
end