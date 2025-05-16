#!/usr/bin/env bash
set -e

run_query() {
	PGPASSWORD=$3 psql -v ON_ERROR_STOP=1 --host="$1" --username="$2" --dbname="$4" -t -c "$5"

}

tsdb_passwd=$(cat /run/secrets/tsdb_passwd)
tsdb_chirpstack_passwd=$(cat /run/secrets/tsdb_chirpstack_passwd)

exists=$(run_query "tsdb" "postgres" $tsdb_passwd "postgres" "SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'chirpstack'")
if [ -z $exists ]; then
	echo -e "Creating chirpstack user"
	run_query "tsdb" "postgres" $tsdb_passwd "postgres" "CREATE USER chirpstack WITH PASSWORD '$tsdb_chirpstack_passwd'"
fi

exists=$(run_query "tsdb" "postgres" $tsdb_passwd "postgres" "SELECT 1 FROM pg_database WHERE datname = 'chirpstack'")
if [ -z $exists ]; then
	echo -e "Creating chirpstack database"
	run_query "tsdb" "postgres" $tsdb_passwd "postgres" "CREATE DATABASE chirpstack WITH OWNER chirpstack"
fi

run_query "tsdb" "chirpstack" $tsdb_chirpstack_passwd  "chirpstack" "CREATE EXTENSION IF NOT EXISTS pg_trgm"
run_query "tsdb" "chirpstack" $tsdb_chirpstack_passwd  "chirpstack" "CREATE EXTENSION IF NOT EXISTS hstore"
