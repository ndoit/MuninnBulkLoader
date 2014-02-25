require 'uri'
require 'net/http'
require 'net/https'
require 'active_support/inflector'
require 'json'
require 'yaml'

def add_to_muninn uri_string, json_object
    config = YAML.load_file("config.yml")
    muninn_host = config["muninn_host"]
    muninn_port = config["muninn_port"]

    http = Net::HTTP.new(muninn_host, muninn_port)
    http.use_ssl = config["muninn_uses_ssl"]
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE #Muninn is using a self-signed cert

    puts "Posting to #{muninn_host}:#{muninn_port}/#{uri_string}..."

    request = Net::HTTP::Post.new("http://#{muninn_host}:#{muninn_port}/#{uri_string}", initheader = {'Content-Type' =>'application/json'})
    request.body = json_object

    return http.request(request)
end

def update_muninn uri_string, json_object
    config = YAML.load_file("config.yml")
    muninn_host = config["muninn_host"]
    muninn_port = config["muninn_port"]

    http = Net::HTTP.new(muninn_host, muninn_port)
    http.use_ssl = config["muninn_uses_ssl"]
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE #Muninn is using a self-signed cert
    
    puts "Posting to #{muninn_host}:#{muninn_port}/#{uri_string}..."

    request = Net::HTTP::Put.new("http://#{muninn_host}:#{muninn_port}/#{uri_string}", initheader = {'Content-Type' =>'application/json'})
    request.body = json_object

    return http.request(request)
end

def extract_file(file_name)
  source_file = File.open(file_name, "r")
  json_objects = []
  current_string = nil
  update_uri = nil
  create_uri = nil
  source_file.each_line do |line|
    line.strip!
    if line != nil && line != ""
      if line == "#END"
        json_objects << { :update_uri => update_uri, :create_uri => create_uri, :json => current_string }
        puts "*** Added.\n"
        current_type = nil
        current_string = nil
      elsif line[0] == "#"
        current_string = ""
        update_uri = line[1,line.length-1]
        first_slash = update_uri.index('/')
        if first_slash == nil
          puts "Target uri must include identifying property: " + line
          return nil
        end
        create_uri = update_uri[0,first_slash].downcase
        puts "*** Adding: #{update_uri}"
      else
        if update_uri == nil
          puts "*** Missing #target_uri declaration at beginning of object."
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
      result = add_to_muninn(json_object[:create_uri], json_object[:json])
      result_json = JSON.parse(result.body)
      if result_json["Success"]
        puts "Created #{json_object[:update_uri]}."
        number_loaded = number_loaded + 1
      else
        result = update_muninn(json_object[:update_uri], json_object[:json])
        result_json = JSON.parse(result.body)
        
        if result_json["Success"]
          puts "Updated #{json_object[:update_uri]}."
          number_loaded = number_loaded + 1
        else
          puts "Failed to load #{json_object[:update_uri]}. It may have dependencies not yet loaded. Will retry if possible."
          error_objects << {
            :create_uri => json_object[:create_uri],
            :update_uri => json_object[:update_uri],
            :json => json_object[:json],
            :message => result_json["Message"]
          }
        end
      end
    end
    json_objects = error_objects
  end
  if error_objects.length > 0
    puts "*** Some objects could not be loaded."
    error_objects.each do |error_object|
      puts "*** Error loading " + error_object[:update_uri] + ": " + error_object[:message] +
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