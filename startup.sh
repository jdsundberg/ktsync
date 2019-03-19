export KINETIC_TIMEOUT=6
export KINETIC_TASK_URI="http://localhost:8080/kinetic-task/app/api/v1"
export KINETIC_DATASTORE_URI="https://localhost/spacename/app/api/v1"
export KINETIC_DATASTORE_USER=admin
export KINETIC_DATASTORE_PASS=admin
java -Dwarbler.port=4567 -Dwarbler.host=0.0.0.0 -jar ktsync.war
