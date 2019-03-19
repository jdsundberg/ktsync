# KTsync

The Kinetic Task Engine by design is asynchronous. The Kinetic Task engine can manage hundreds to thousands of different workflows. Some workflows could take days or weeks to be completed (example: a person needs to approve an action, before another action can start), and other workflows could be automated and completed in less than a second (example: add this person to an email group).

KTSync is designed to allow you to use the power of the Kinetic Task engine in a synchronous fashion (specifically for those fast running workflows).

Use this web application to wrap the asynchronous Kinetic Task Engine

## How it works

1. Client sends a JSON encoded body to KTSync
2. KTSync will add a unique GUID to your JSON body
3. KTSync will call the task tree requested with the JSON body
4. KTSync will then poll the Kinetic Datastore for the GUID provided at 100ms intervals
5. When KTSync finds the Datastore record for the GUID provided ... it will return to the client the Body found in the Datastore record
6. If no Datastore record is found within a preconfigured TIMEOUT period, the KTSync server will return with a timeout message and the GUID used for the identifier

In the meantime (after step 3 above)

1. The Kinetic Task engine will run the tree requested with the JSON body provided
2. The tree should be configured so that the last node in the tree will create the Datastore record for the GUID provided and populate the Body field with the desired values

(The above Task process (Steps 1-2 above) generally should be less than a second, however, no matter how long it takes ... it will finish)
(See TIMEOUT)

## TIMEOUT

If the original KTSync request returned with a timeout, you can call the KTSync with the GUID provided to check status later.
The status request is an API call which will lookup that GUID in the Datastore and return the value of the JSON body if a Datastore is found.
If it is not found, KTSync will return a "not found" status.

## Not found

If the call to the API status does not find the GUID, it will return with a "not found" status. "Not found" means the Datastore does not have a record for that GUID. That can be for a couple reasons:

1. The Task Engine run for that GUID has not yet finished
2. Their was an Error in running the tree, and the run is currently paused waiting for administration assistance.

start the server with: (or - whatever port you want to run it on)
java -jar ktsync.war
(Will run it on port 8080 for 0.0.0.0)

To change port / listen address:
java -Dwarbler.port=4567 -Dwarbler.host=0.0.0.0 -jar ktsync.war

How to run from a client:

```
curl -H "Content-Type: application/json" -X POST http://localhost:4567/ktsync/Playground/Say/Submit -d "{\"say_what\": \"The time is 4 55 P M\"}"
```

HOWEVER -- it is a bad idea to "wait forever" - so there is a timeout value.
If the task run takes longer than the timeout value in seconds...
then the system will return an id and a "timeout" Status

Example return status from a timeout:

```
{"id":"24dcfe49-8771-434b-9a08-2c8285729f8a","status":"timeout","results":""}
```

If you run a process that times out ... you can check the status of the id

```
curl http://localhost:4567/status/24dcfe49-8771-434b-9a08-2c8285729f8a
```

Example return status from a timeout:

```
{"id":"24dcfe49-8771-434b-9a08-2c8285729f8a","status":"complete","results":"sample return data"}
```

## Building KTSync

I use jruby-9.2.5.0

To build the executable war

```
bundle install
gem install warbler
warble executable war
```

## Environment variables

Set these environment variables if running by hand.

```
export KINETIC_TASK_URI="http://localhost:8080/kinetic-task/app/api/v1"
export KINETIC_TIMEOUT=6
export KINETIC_DATASTORE_URI="https://localhost/spacename/app/api/v1"
export KINETIC_DATASTORE_USER=admin
export KINETIC_DATASTORE_PASS=admin
```

Run the app on port 4567

```
java -Dwarbler.port=4567 -Dwarbler.host=0.0.0.0 -jar ktsync.war
```

## Testing

```
curl http://localhost:4567/status

curl http://localhost:4567/status/123
```

## Running in Docker

Add the environment from above to a file called env.list then run

```
docker run -p 4567:4567 --env-file ./env.list jdsundberg/ktsync
```
