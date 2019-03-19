require 'rubygems'
require 'sinatra'
require 'rest-client'
require 'securerandom'
require 'unf'
require 'base64'


# TODO
# https://zauberfinger.wordpress.com/2014/09/23/deploy-a-sinatra-app-with-docker/

def configMessage(g,msg)
  g["config"]["configMessage"] += msg += "\n"
  ## THIS DOES NOT WORK ... I HAVE BEEN UNABLE TO SHUTDOWN A SINATRA APP RELIABLY
  # Sinatra::Application.quit!
end

global = Hash.new
global["config"]=Hash.new
global["config"]["configMessage"] = ""
global["config"]["kinetic_task_uri"] = ENV["KINETIC_TASK_URI"] || configMessage(global,"KINETIC_TASK_URI not set")
global["config"]["kinetic_datastore_uri"] = ENV["KINETIC_DATASTORE_URI"] || configMessage(global,"KINETIC_DATASTORE_URI not set")
global["config"]["kinetic_datastore_user"] = ENV["KINETIC_DATASTORE_USER"] || configMessage(global,"KINETIC_DATASTORE_USER not set")
global["config"]["kinetic_datastore_pass"] = ENV["KINETIC_DATASTORE_PASS"] || configMessage(global,"KINETIC_DATASTORE_PASS not set")
global["config"]["kinetic_timeout"] = ENV["KINETIC_TIMEOUT"] || configMessage(global,"KINETIC_TIMEOUT not set")
global["config"]["kinetic_timeout"] = ENV["KINETIC_TIMEOUT"].to_i || configMessage(global,"KINETIC_TIMEOUT not set") # will set to 0 if not exist


def findSubmission(global,kinetic_sync_id)

  uri = global["config"]["kinetic_datastore_uri"]
  uri = "#{uri}/datastore/forms/synchronized-task-log/submissions"
  uri = "#{uri}?include=values&direction=ASC&limit=25"
  uri = "#{uri}&index=values[SyncId]"
  uri = "#{uri}&q=(values[SyncId]=\"#{kinetic_sync_id}\")"

  user = global["config"]["kinetic_datastore_user"]
  pass = global["config"]["kinetic_datastore_pass"]

  response = ""

  puts "URI: #{uri}"

  begin
    response = RestClient::Request.execute method: :get, url: uri, \
    user: user, password: pass, \
    headers: {content_type: :json, accept: :json}
  rescue StandardError => e
    puts "Error in findSubmission for #{kinetic_sync_id} #{e.message}"
  end

puts "Response: #{response.inspect}"

  return response
end

def send_request_to_task(global,request,params)
  treename = params['splat'][0]

  request.body.rewind  # in case someone already read it
  data = JSON.parse request.body.read

  userHash = getUserCredentials(request.env["HTTP_AUTHORIZATION"])
  user = userHash["username"]
  password = userHash["password"]

  # add my kinetic_sync_id
  kinetic_sync_id = SecureRandom.uuid

  data["kinetic_sync_id"]=kinetic_sync_id

  # Pass the request onto Kinetic Task
  uri = "#{global["config"]["kinetic_task_uri"]}/run-tree/#{treename}"

  retval = Hash.new
  retval["kinetic_sync_id"]=kinetic_sync_id
  retval["status"]="sent"

  begin
    if (user.to_s.empty?) then
      response = RestClient::Request.execute method: :post, url: uri, \
      payload: data.to_json, \
      headers: {content_type: :json, accept: :json}
    else
      response = RestClient::Request.execute method: :post, url: uri, \
      user: user, password: pass, \
      payload: data.to_json, \
      headers: {content_type: :json, accept: :json}
    end

  rescue StandardError => e
    retval["status"]= "failed"
    retval["results"] = e.message
  end

  return retval

end

def getUserCredentials(authorization)
  x = Hash.new
  x["username"]=""
  x["password"]=""
  unless authorization.nil?
    authorization.gsub!(/Basic /,'')
    decodestring = Base64.decode64(authorization)
    vals = decodestring.split(':')
    user = vals.shift
    password = vals.join(":") # if the password has a :
    x["username"]=user
    x["password"]=password
  end
  return x
end

get '/status/:kinetic_sync_id' do
    kinetic_sync_id = params['kinetic_sync_id']

    responseJSON = findSubmission(global,kinetic_sync_id)

    response = JSON.parse(responseJSON)

    retval = Hash.new
    retval["kinetic_sync_id"]=kinetic_sync_id

    # Need to check that we found any at all
    if response == "" || response["submissions"].count == 0 then
      retval["status"]= "Not found"
      return retval.to_json
    else
      retval["status"]=response["submissions"].first["values"]["SyncStatus"]
      retval["results"]=response["submissions"].first["values"]["SyncResults"]
      return retval.to_json
    end
end


# Should add a test to connect to task engine and datastore
get '/status' do
  if (global["config"]["configMessage"] == "")
    return "Alive!"
  else
    return global["config"]["configMessage"]
  end
end

# will not wait for completetion - will return with id of run for
# checking status
post '/ktrun/*' do
  retval = send_request_to_task(global,request,params)
  return retval.to_json
end


# will wait until timeout - will return with id of run for
# checking status (if timeout)
# will return with id/status/results if completed within timeout
post '/ktsync/*' do
  retval = send_request_to_task(global,request,params)

  start_time = Time.now.to_f
  retval["status"]="complete"
  while (true) do


    sleep 0.1 # tenth of a second
    responseJSON = findSubmission(global,retval["kinetic_sync_id"])
    response = JSON.parse(responseJSON)

    # Need to check that we found any at all
    if response == "" || response["submissions"].count == 1 then
      retval["status"]=response["submissions"].first["values"]["SyncStatus"]
      retval["results"]=response["submissions"].first["values"]["SyncResults"]
      return retval.to_json
    end


    puts "TimeNow #{Time.now.to_f}"
    puts "StartTime = #{start_time}"
    puts "Config: #{global["config"]["kinetic_timeout"]}"

    # timeout
    if ((Time.now.to_f - start_time) > global["config"]["kinetic_timeout"]) then
      retval["status"] = "timeout"
      return retval.to_json
    end
  end

  return retval.to_json

end
