FROM openjdk

ADD ktsync.war /opt/ktsync-app/
EXPOSE 4567
CMD java -Dwarbler.port=4567 -Dwarbler.host=0.0.0.0 -jar  /opt/ktsync-app/ktsync.war
