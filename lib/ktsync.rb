require 'rubygems'
require 'sinatra'
require 'rest-client'
require 'securerandom'
require 'unf'
require 'base64'


# TODO
# https://zauberfinger.wordpress.com/2014/09/23/deploy-a-sinatra-app-with-docker/


global = Hash.new
global["config"]=Hash.new
global["config"]["kinetic_task_uri"] = ENV["KINETIC_TASK_URI"] || abort("KINETIC_TASK_URI not set")
global["config"]["kinetic_datastore_uri"] = ENV["KINETIC_DATASTORE_URI"] || abort("KINETIC_DATASTORE_URI not set")
global["config"]["kinetic_datastore_user"] = ENV["KINETIC_DATASTORE_USER"] || abort("KINETIC_DATASTORE_USER not set")
global["config"]["kinetic_datastore_pass"] = ENV["KINETIC_DATASTORE_PASS"] || abort("KINETIC_DATASTORE_PASS not set")
global["config"]["kinetic_callback_uri"] = ENV["KINETIC_CALLBACK_URI"] || abort("KINETIC_CALLBACK_URI not set")
global["config"]["kinetic_timeout"] = ENV["KINETIC_TIMEOUT"].to_i || abort("KINETIC_TIMEOUT not set")


# I use this just during dev ... do not include
# get '/global' do
#   global.to_json
# end


def findSubmission(global,id)
  uri = global["config"]["kinetic_datastore_uri"]
  uri = "#{uri}/kapps/admin/forms/synchronized-task-log/submissions"
  uri = "#{uri}?include=values&timeline=createdAt&direction=DESC&limit=25"
  uri = "#{uri}&q=(values[SyncId]=\"#{id}\")"

  user = global["config"]["kinetic_datastore_user"]
  pass = global["config"]["kinetic_datastore_pass"]

  response = ""

  begin
    response = RestClient::Request.execute method: :get, url: uri, \
    user: user, password: pass, \
    headers: {content_type: :json, accept: :json}
  rescue StandardError => e
    puts "Error in findSubmission for #{id} #{e.message}"
  end

  return JSON.parse(response)
end

get '/status/:id' do
    id = params['id']

    response = findSubmission(global,id)

    # Need to check that we found any at all
    if response["submissions"].count != 1 then
      retval = Hash.new
      retval["id"]=id
      retval["status"]= "error"
      retval["results"]= %Q!{"Message":"Found: #{response["submissions"].count} submissions in datastore"}!

      return retval.to_json

    else
      retval = Hash.new
      retval["id"]=id
      retval["status"]=response["submissions"].first["values"]["SyncStatus"]
      retval["results"]=response["submissions"].first["values"]["SyncResults"]

      return retval.to_json
    end
end

get '/status' do
  return "Alive!"
end


# Kinetic Task calls this -- and updates status/results
post '/ktcallback' do

  request.body.rewind  # in case someone already read it
  data = JSON.parse request.body.read

  id = ""
  results = ""
  status = "complete"

  if(data.has_key?("callbackid") && data.has_key?("results")) then
    id = data["callbackid"]
    results = data["results"]
  else
    %Q!{"status":"failure - missing callbackid / results"}!
  end

  # Update Datastore
  update_datastore_record(global,id,status,results)

  # Update Memory - for "realtime synchronize"
  mutex = Mutex.new
  mutex.synchronize {
    global[id] = Hash.new
    global[id]["status"] = status
    global[id]["results"] = results
  }


  %Q!{"status":"complete"}!

end


def create_datastore_record(global,id,status,results)

  uri = global["config"]["kinetic_datastore_uri"]
  uri = "#{uri}/kapps/admin/forms/synchronized-task-log/submissions?completed=false"

  user = global["config"]["kinetic_datastore_user"]
  pass = global["config"]["kinetic_datastore_pass"]

  data = Hash.new
  data["values"]=Hash.new
  data["values"]["Status"]="active"
  data["values"]["SyncId"]=id
  data["values"]["SyncStatus"]=status
  data["values"]["SyncResults"]=results


  begin
    response = RestClient::Request.execute method: :post, url: uri, \
    user: user, password: pass, \
    payload: data.to_json, \
    headers: {content_type: :json, accept: :json}
  rescue StandardError => e
    puts "Error in create_datastore_record for #{id} #{e.message}"
  end

end


def update_datastore_record(global,id,status,results)

  response = findSubmission(global,id)

  # Need to check that we found any at all
  # What should I do - should I return if I didnt find it?
  if response["submissions"].count != 1 then
    return "Did not find #{id} in datastore"
  end

  submissionId = response["submissions"].first["id"]

  uri = global["config"]["kinetic_datastore_uri"]
  uri = "#{uri}/submissions/#{submissionId}"

  user = global["config"]["kinetic_datastore_user"]
  pass = global["config"]["kinetic_datastore_pass"]

  data = Hash.new
  data["coreState"]="Submitted"
  data["values"]=Hash.new
  data["values"]["SyncStatus"]=status
  data["values"]["SyncResults"]=results

  begin
    response = RestClient::Request.execute method: :put, url: uri, \
    user: user, password: pass, \
    payload: data.to_json, \
    headers: {content_type: :json, accept: :json}
  rescue StandardError => e
    puts "Error in update_datastore_record for #{id} #{e.message}"
  end

end


def send_request_to_task(global,wait,request,params,user,pass)
  treename = params['splat'][0]

  request.body.rewind  # in case someone already read it
  data = JSON.parse request.body.read

  # https://vaneyckt.io/posts/ruby_concurrency_in_praise_of_the_mutex/
  # visibility.rb

  id = SecureRandom.uuid
  mutex = Mutex.new
  mutex.synchronize {
    global[id] = Hash.new
    global[id]["status"]="started"
    global[id]["results"]=""

  }
  # Record into Datastore
  create_datastore_record(global,id,"started","")

  data["kinetic_callback_id"]=id
  data["kinetic_callback_uri"]=global["config"]["kinetic_callback_uri"]

  # Pass the request onto Kinetic Task
  uri = "#{global["config"]["kinetic_task_uri"]}/run-tree/#{treename}"

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
    status = "failed"
    update_datastore_record(global,id,status,e.message)
    retval = Hash.new
    retval["id"]=id
    retval["status"]= status
    retval["results"] = e.message
    return retval.to_json
  end

  # if not waiting just return the id
  if(wait != "true") then
    retval = Hash.new
    retval["id"]=id
    return retval.to_json
  end

  # By default - assume complete - however we may timeout ... catch that
  # and return with status= "timeout" and the id - so status can be checked
  # later
  status = "complete"
  start_time = Time.now.to_f
  thr = Thread.new do
    while mutex.synchronize { global[id]["status"] == "started"} do
      sleep 0.1 # tenth of a second
      if (Time.now.to_f - start_time > global["config"]["kinetic_timeout"]) then
        status = "timeout"
        break # exits
      end
    end
  end
  thr.join

  # delete the id ... as we only need it when running in wait mode
  # and we have not yet timed out
  # once we timeout - we will be checking the datastore for status
  results = ""
  mutex.synchronize {
    results = global[id]["results"]
    global.delete(id)
  }

  retval = Hash.new
  retval["id"]=id
  retval["status"]=status
  retval["results"]=results

  return retval.to_json


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

# will not wait for completetion - will return with id of run for
# checking status
post '/ktrun/*' do
  userHash = getUserCredentials(request.env["HTTP_AUTHORIZATION"])
  user = userHash["username"]
  password = userHash["password"]
  send_request_to_task(global,"false",request,params,user,password)
end

# will wait until timeout - will return with id of run for
# checking status (if timeout)
# will return with id/status/results if completed within timeout
post '/ktsync/*' do
  userHash = getUserCredentials(request.env["HTTP_AUTHORIZATION"])
  user = userHash["username"]
  password = userHash["password"]
  send_request_to_task(global,"true",request,params,user,password)
end
