# ktsync

The Kinetic Task Engine by design is asynchronous. You may ask Task to run a tree - but it could take 3 hours to run. However, you may have some trees that run in a second - or less. 
Use this web application to wrap the asynchronous Kinetic Task Engine

This server will pass your request onto Kinetic Task ... then will setup a couple
callbacks in order to wait for the process to finish - when finished will return the results
to the caller.
Note: The process being called in Kinetic needs to include a "callback" node using a Rest POST function to update this running web application with the "results".

start the server with: (or - whatever port you want to run it on)
java -jar ktsync-app.war
(Will run it on port 8080 for 0.0.0.0)

To change port / listen address:
java -Dwarbler.port=4567 -Dwarbler.host=0.0.0.0 -jar ktsync-app.war


How to run from a client:

curl -H "Content-Type: application/json" -X POST http://localhost:4567/ktsync/Playground/Say/Submit -d "{\"say_what\": \"The time is 4 55 P M\"}"


HOWEVER -- it is a bad idea to "wait forever" - so there is a timeout value.
If the task run takes longer than the timeout value in seconds...
then the system will return an id and a "timeout" Status

Example return status from a timeout:
{"id":"24dcfe49-8771-434b-9a08-2c8285729f8a","status":"timeout","results":""}

If you run a process that times out ... you can check the status of the id

Webcall:
curl http://localhost:4567/status/24dcfe49-8771-434b-9a08-2c8285729f8a

Example return status from a timeout:
{"id":"24dcfe49-8771-434b-9a08-2c8285729f8a","status":"complete","results":"sample return data"}
