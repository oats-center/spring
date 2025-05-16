#!/bin/ash
set -e

/bin/sed "s/\$nats_chirpstack_passwd/$nats_chirpstack_passwd/g" /mosquitto/config/mosquitto-pre-expand.conf > /mosquitto/config/mosquitto.conf 
exec /docker-entrypoint.sh $@
