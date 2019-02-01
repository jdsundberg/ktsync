bundle install

gem install warbler

warble executable war

export KINETIC_TIMEOUT=6
export KINETIC_CALLBACK_URI="http://localhost:4567/ktcallback"
export KINETIC_TASK_URI="http://localhost:8080/kinetic-task/app/api/v1"

export KINETIC_DATASTORE_URI="https://localhost/spacename/app/api/v1"
export KINETIC_DATASTORE_USER=admin
export KINETIC_DATASTORE_PASS=admin

curl http://localhost:4567/status

curl http://localhost:4567/status/123
