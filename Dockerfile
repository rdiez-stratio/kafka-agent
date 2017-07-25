# Kafka container
FROM qa.stratio.com/stratio/ubuntu-base:16.04

ARG VERSION

ENV SCALA_VERSION 2.11
ENV KAFKA_VERSION 0.10.0.1
ENV KAFKA_HOME /opt/kafka_"$SCALA_VERSION"-"$KAFKA_VERSION"

# Install Kafka
RUN wget -q http://thirdparties.repository.stratio.com/kafkastratio/kafka_"$SCALA_VERSION"-"$KAFKA_VERSION".tgz -O /tmp/kafka_"$SCALA_VERSION"-"$KAFKA_VERSION".tgz && \
    tar xfz /tmp/kafka_"$SCALA_VERSION"-"$KAFKA_VERSION".tgz -C /opt && \
    rm /tmp/kafka_"$SCALA_VERSION"-"$KAFKA_VERSION".tgz

# Install jq tool
RUN wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 -O /usr/bin/jq

# Retrieve janithor
RUN wget http://sodio.stratio.com/repository/releases/com/stratio/janithor/0.1.1/janithor-0.1.1.jar -O /tmp/janithor.jar

# Retrieve kms utils file

RUN wget http://sodio.stratio.com/repository/paas/kms_utils/0.2.1/kms_utils-0.2.1.sh -O /tmp/kms_utils.sh

# Add producer and consumer properties file
#ADD producer.ssl.properties $KAFKA_HOME/config/
ADD consumer.ssl.properties.template $KAFKA_HOME/config/
#ADD truststore.jks $KAFKA_HOME/config/
#ADD keystore.jks $KAFKA_HOME/config/

# Add entrypoint and make it executable
ADD agents.sh /usr/bin/agents.sh
RUN chmod a+x /usr/bin/agents.sh

ENTRYPOINT ["agents.sh"]
