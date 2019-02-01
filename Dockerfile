FROM ubuntu:14.04

RUN apt-get update -y
RUN apt-get install -y openjdk-7-jre

ADD ktsync-app.war /opt/ktsync-app/

EXPOSE 8080

CMD java -jar /opt/ktsync-app/ktsync-app.war
