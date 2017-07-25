#!/bin/bash
set -x

# Load kms utils script
.  /tmp/kms_utils.sh

function _error_exit
{
  # 1 argument: string containing descriptive error message
  echo "${PROGNAME}: ${1:-"Unknown Error"}" 1>&2
  exit 1
}

function _envsubst() {
    local replace_key=$1
    local replace_val=$2
    local destination=$3
    sed -i 's#'$replace_key'#'$replace_val'#g' $destination
}

PROGNAME=$(basename $0)

# Define number of records
if [ -z "${INSTANCE}" ]; then
  INSTANCE=kafka-sec
fi

SERVICE_PATH=/service/${INSTANCE}/v1/cluster

# Define number of records
if [ -z "${NUMBER_OF_RECORDS}" ]; then
  NUMBER_OF_RECORDS=1000
fi

# Define record size in bytes
if [ -z "${RECORD_SIZE}" ]; then
  RECORD_SIZE=100
fi

# Define buffer memory
if [ -z "${BUFFER_MEMORY}" ]; then
  BUFFER_MEMORY=67108864
fi

# Define batch size
if [ -z "${BATCH_SIZE}" ]; then
  BATCH_SIZE=8196
fi

# Define consumer threads
if [ -z "${THREAD_NUMBERS}" ]; then
  THREAD_NUMBERS=1
fi

# Define producer throughput
if [ -z "${THROUGHPUT}" ]; then
  THROUGHPUT=-1 #Maximum speed
fi

# Define ack mode  Async=1, Sync=-1
if [ -z "${ASYNC}" ]; then
  ASYNC=1
fi

# Define topic partitions
if [ -z "${PARTITIONS}" ]; then
  PARTITIONS=1
fi

# Define topic replication factor
if [ -z "${REPLICATION_FACTOR}" ]; then
  REPLICATION_FACTOR=1
fi

# Define zookeeper url
if [ -z "${ZOOKEEPER}" ]; then
  ZOOKEEPER=zk-0001-zookeeperkafka.service.paas.labs.stratio.com:2181
fi

# Define zookeeper chroot
if [ -z "${CHROOT}" ]; then
  CHROOT=dcos-service-kafka-sec
fi

# Define zookeeper chroot
if [ -z "${TLS}" ]; then
  TLS=true
fi

if [ $TLS == "true" ]; then
  PROTOCOL=SSL
else
  PROTOCOL=PLAINTEXT
fi

# Define Consumer socket-buffer-size chroot
if [ -z "${REPORT_INTERVAL}" ]; then
  REPORT_INTERVAL="$(expr $NUMBER_OF_RECORDS / 10)"
fi

# Define Vault Token from Dynamic Authentication
if [ -z "${VAULT_TOKEN}" ]; then
  VAULT_TOKEN="9430f5cf-5f3a-4ed2-ff73-4148355ddb75"
fi

# Define Vault port
if [ -z "${VAULT_HOSTS}" ]; then
  VAULT_HOSTS="gosec1.node.paas.labs.stratio.com"
fi

# Define Vault port
if [ -z "${VAULT_PORT}" ]; then
  VAULT_PORT=8200
fi

# Define Vault port
if [ -z "${AGENT}" ]; then
  AGENT="consumer"
fi

# Define consumer group
if [ -z "${CONSUMER_GROUP}" ]; then
  CONSUMER_GROUP="test-consumer-group"
fi



# Filling broker list with mesos dns information
if [ -z "$BROKER_LIST" ]; then

    # Retrieve token from dcos to run the query
    while [ -z "$TOKEN" ]; do
      TOKEN=$(java -jar /tmp/janithor.jar -o token -u "https://${SERVICE_ENDPOINT}" -sso ${DCOS_USER}:${DCOS_PASSWORD})
    done

    #response=$(curl "http://$KAFKA_SCHEDULER_IP:$PORT/v1/cluster" --write-out '\n%{http_code}')
    response=$(curl -s --header "Cookie:dcos-acs-auth-cookie=${TOKEN}" -k "https://$SERVICE_ENDPOINT${SERVICE_PATH}" --write-out '\n%{http_code}')
    data=$(echo "$response" | head -1 )
    status_code=$(echo "$response" | tail -1)
    if [[ $status_code == 200 ]]; then
       endpoints=$(echo $data | jq  ' .endpoints  |  length')
       for ((i = 0 ; i < $endpoints ; i++ ))
       do
         host=$(echo $data | jq  " .endpoints  | .[$i] | .host"  | sed 's/\"//g') #Removing the " caracters
         port=$(echo $data | jq  " .endpoints  | .[$i] | .port" )
         BROKER_LIST+=$host:$port
         if [[ "$i" -lt "$endpoints-1" ]]; then
           BROKER_LIST+=","
         fi
       done
    else
      _error_exit "$LINENO: Error retrieving information from kafka scheduler rest API"
    fi
fi

# Setting up the default topic
if [ -z "$TOPIC" ]; then
  TOPIC="datio"
fi

# Retrieve data from VAULT
if [ ! -z "VAULT_TOKEN" ] && [ ! -z "VAULT_PORT" ] && [ ! -z "VAULT_HOSTS" ]; then

  # Password retrieval
  PTR_KEYSTORE_PASS_AUX="${INSTANCE^^}"_"KEYSTORE"_PASS
  PTR_KEYSTORE_PASS="${PTR_KEYSTORE_PASS_AUX//-/_}"
  PTR_TRUSTORE_PASS=DEFAULT_KEYSTORE_PASS

   # Generate service trustore
   getCAbundle "$KAFKA_HOME/config/" "JKS" "truststore.jks"
   if [ $? -ne 0 ]; then
     _error_exit "$LINENO: Error importing certificate to ${KAFKA_HOME}/config/$FILE_TRUSTORE"
   fi

   # Get service certificates (generation of the keystore.jks)
   getCert "userland" $INSTANCE "$AGENT.kafka-sec.mesos" "JKS" $KAFKA_HOME/config/
   if [ $? -ne 0 ] || [ ! -f "${KAFKA_HOME}/config/$AGENT.kafka-sec.mesos.jks" ]; then
      _error_exit "$LINENO: Error getting certificates from Vault. Please review yout vault (host, port and token),
       and the secret located in /$CLUSTER/certificates/$INSTANCE"
   fi

else
  _error_exit "$LINENO: Some Vault variables information is missing"
fi


# Defining if the agent is a producer or not
if [[ "$AGENT" == "producer" ]];then
  #Create a topic
  $KAFKA_HOME/bin/kafka-topics.sh --zookeeper ${ZOOKEEPER}/${CHROOT} \
  --create --topic $TOPIC --partitions $PARTITIONS --replication-factor $REPLICATION_FACTOR --if-not-exists

    if [ $TLS == "true" ];then
      $KAFKA_HOME/bin/kafka-run-class.sh  org.apache.kafka.tools.ProducerPerformance \
       --topic $TOPIC \
       --num-records ${NUMBER_OF_RECORDS} \
       --record-size ${RECORD_SIZE} \
       --throughput $THROUGHPUT \
       --producer-props acks=$ASYNC \
                        bootstrap.servers=$BROKER_LIST \
                        security.protocol=SSL  \
                        ssl.truststore.location=$KAFKA_HOME/config/truststore.jks \
                        ssl.truststore.password=${!PTR_TRUSTORE_PASS}  \
                        ssl.keystore.location=$KAFKA_HOME/config/$AGENT.kafka-sec.mesos.jks \
                        ssl.keystore.password=${!PTR_KEYSTORE_PASS} \
                        buffer.memory=${BUFFER_MEMORY} \
                        batch.size=${BATCH_SIZE} \
      &&  tail -f /dev/null
    else
      $KAFKA_HOME/bin/kafka-run-class.sh  org.apache.kafka.tools.ProducerPerformance \
       --topic $TOPIC \
       --num-records ${NUMBER_OF_RECORDS} \
       --record-size ${RECORD_SIZE} \
       --throughput $THROUGHPUT \
       --producer-props acks=$ASYNC \
                        bootstrap.servers=$BROKER_LIST \
                        security.protocol=PLAINTEXT  \
                        buffer.memory=${BUFFER_MEMORY} \
                        batch.size=${BATCH_SIZE} \
      &&  tail -f /dev/null
    fi
else
  if [ $TLS == "true" ];then

    # Rewrite the consumer template
    _envsubst SECURITY_PROTOCOL "$PROTOCOL" $KAFKA_HOME/config/consumer.ssl.properties.template
    _envsubst TRUSTSTORE_LOCATION "$KAFKA_HOME/config/truststore.jks" $KAFKA_HOME/config/consumer.ssl.properties.template
    _envsubst TRUSTSTORE_PASSWORD "${!PTR_TRUSTORE_PASS}" $KAFKA_HOME/config/consumer.ssl.properties.template
    _envsubst KEYSTORE_LOCATION "$KAFKA_HOME/config/$AGENT.kafka-sec.mesos.jks" $KAFKA_HOME/config/consumer.ssl.properties.template
    _envsubst KEYSTORE_PASSWORD "${!PTR_KEYSTORE_PASS}" $KAFKA_HOME/config/consumer.ssl.properties.template
    _envsubst CONSUMER_GROUP "${CONSUMER_GROUP}" $KAFKA_HOME/config/consumer.ssl.properties.template

    $KAFKA_HOME/bin/kafka-consumer-perf-test.sh \
      --new-consumer \
      --broker-list $BROKER_LIST \
      --messages ${NUMBER_OF_RECORDS} \
      --message-size ${RECORD_SIZE} \
      --topic $TOPIC \
      --threads $THREAD_NUMBERS \
      --consumer.config $KAFKA_HOME/config/consumer.ssl.properties.template \
      --show-detailed-stats \
      --reporting-interval $REPORT_INTERVAL \
    &&  tail -f /dev/null
  else
    _envsubst SECURITY_PROTOCOL "$PROTOCOL" $KAFKA_HOME/config/consumer.ssl.properties.template
    _envsubst CONSUMER_GROUP "${CONSUMER_GROUP}" $KAFKA_HOME/config/consumer.ssl.properties.template
    
    $KAFKA_HOME/bin/kafka-consumer-perf-test.sh \
      --new-consumer \
      --broker-list $BROKER_LIST \
      --messages ${NUMBER_OF_RECORDS} \
      --message-size ${RECORD_SIZE} \
      --topic $TOPIC \
      --threads $THREAD_NUMBERS \
      --show-detailed-stats \
      --reporting-interval $REPORT_INTERVAL \
    &&  tail -f /dev/null
  fi
fi
