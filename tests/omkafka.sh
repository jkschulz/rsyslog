#!/bin/bash
# added 2017-05-03 by alorbach
# This file is part of the rsyslog project, released under ASL 2.0
export TESTMESSAGES=50000
export TESTMESSAGESFULL=$TESTMESSAGES

# Generate random topic name
export RANDTOPIC=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)

# enable the EXTRA_EXITCHECK only if really needed - otherwise spams the test log
# too much
#export EXTRA_EXITCHECK=dumpkafkalogs
echo ===============================================================================
echo \[omkafka.sh\]: Create kafka/zookeeper instance and $RANDTOPIC topic
. $srcdir/diag.sh download-kafka
. $srcdir/diag.sh stop-zookeeper
. $srcdir/diag.sh stop-kafka
. $srcdir/diag.sh start-zookeeper
. $srcdir/diag.sh start-kafka
# create new topic
. $srcdir/diag.sh create-kafka-topic $RANDTOPIC '.dep_wrk' '22181'

echo \[omkafka.sh\]: Give Kafka some time to process topic create ...
sleep 5

echo \[omkafka.sh\]: Init Testbench 
. $srcdir/diag.sh init

# --- Create/Start omkafka sender config 
export RSYSLOG_DEBUGLOG="log"
generate_conf
add_conf '
main_queue(queue.timeoutactioncompletion="60000" queue.timeoutshutdown="60000")

module(load="../plugins/omkafka/.libs/omkafka")
module(load="../plugins/imtcp/.libs/imtcp")
input(type="imtcp" port="'$TCPFLOOD_PORT'")	/* this port for tcpflood! */

template(name="outfmt" type="string" string="%msg:F,58:2%\n")

local4.* action(	name="kafka-fwd" 
	type="omkafka" 
	topic="'$RANDTOPIC'" 
	broker="localhost:29092" 
	template="outfmt" 
	confParam=[	"compression.codec=none",
			"socket.timeout.ms=10000",
			"socket.keepalive.enable=true",
			"reconnect.backoff.jitter.ms=1000",
			"queue.buffering.max.messages=10000",
			"enable.auto.commit=true",
			"message.send.max.retries=1"]
	topicConfParam=["message.timeout.ms=10000"]
	partitions.auto="on"
	closeTimeout="60000"
	resubmitOnFailure="on"
	keepFailedMessages="on"
	failedMsgFile="omkafka-failed.data"
	action.resumeInterval="1"
	action.resumeRetryCount="2"
	queue.saveonshutdown="on"
	)
'

echo \[omkafka.sh\]: Starting sender instance [omkafka]
startup
# --- 

echo \[omkafka.sh\]: Inject messages into rsyslog sender instance  
tcpflood -m$TESTMESSAGES -i1

echo \[omkafka.sh\]: Stopping sender instance [omkafka]
shutdown_when_empty
wait_shutdown

kafkacat -b localhost:29092 -e -C -o beginning -t $RANDTOPIC -f '%s'> $RSYSLOG_OUT_LOG
kafkacat -b localhost:29092 -e -C -o beginning -t $RANDTOPIC -f '%p@%o:%k:%s' > $RSYSLOG_OUT_LOG.extra

# Delete topic to remove old traces before
# . $srcdir/diag.sh delete-kafka-topic $RANDTOPIC '.dep_wrk' '22181'

# Dump Kafka log
# uncomment if needed . $srcdir/diag.sh dump-kafka-serverlog

echo \[omkafka.sh\]: stop kafka instance
. $srcdir/diag.sh stop-kafka

# STOP ZOOKEEPER in any case
. $srcdir/diag.sh stop-zookeeper

# Do the final sequence check
seq_check 1 $TESTMESSAGESFULL -d

echo success
exit_test