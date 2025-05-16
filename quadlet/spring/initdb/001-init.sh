#!/usr/bin/env bash
set -e

run_query() {
	PGPASSWORD=$3 psql -v ON_ERROR_STOP=1 --host="$1" --username="$2" --dbname="$4" -t -c "$5"
}

tsdb_passwd=$(cat /run/secrets/tsdb_passwd)
tsdb_data_passwd=$(cat /run/secrets/tsdb_data_passwd)

exists=$(run_query "tsdb" "postgres" $tsdb_passwd "postgres" "SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'data'")
if [ -z $exists ]; then
	echo -e "Creating data user"
	run_query "tsdb" "postgres" $tsdb_passwd "postgres" "CREATE USER data WITH PASSWORD '$tsdb_data_passwd'"
fi

exists=$(run_query "tsdb" "postgres" $tsdb_passwd "postgres" "SELECT 1 FROM pg_database WHERE datname = 'data'")
if [ -z $exists ]; then
	echo -e "Creating data database"
	run_query "tsdb" "postgres" $tsdb_passwd "postgres" "CREATE DATABASE data WITH OWNER data"
fi

run_query "tsdb" "postgres" $tsdb_passwd "data" "CREATE EXTENSION IF NOT EXISTS postgis"
run_query "tsdb" "postgres" $tsdb_passwd "data" "CREATE EXTENSION IF NOT EXISTS timescaledb"

PGPASSWORD=$tsdb_data_passwd psql -v ON_ERROR_STOP=1 --host="tsdb" --username="data" --dbname="data" <<-EOSQL
  --
  -- A "project" is just a logical collection of sensors for a particular purpose. A sensor can be in more than one project.
  --
  CREATE TABLE IF NOT EXISTS project (
    project_id serial,
    name text NOT NULL,
    notes text,

    PRIMARY KEY (project_id)
  );

  --
  -- A device entry represents a physical thing which somehow collectors or transports data
  -- device_id is intended to be unqiue over all things. To accomplish this, each type of device is put behind a series of namespaces until
  -- (ideally) a fundmentally unqiue ID is found (like a MAC address or serial number).
  --    For example: follows this standard:
  --      * LoRaWAN -> lorawan:<device_eui>
  --      * AOR -> aor:<station-id>:<sensor-type>:<sensor-serial-number>
  --      * ...TDB...
  --
  CREATE TABLE IF NOT EXISTS device (
    device_id text,
    metadata_table text NOT NULL, -- "lorawan", "isoblue", etc.
    notes text,

    PRIMARY KEY (device_id)
  );

  --
  -- Links sensors to a project.
  -- One sensor may be part of more than one sensor.
  -- A physical sensor may have a life longer then a given project. Start/stop time are project specific.
  --
  CREATE TABLE IF NOT EXISTS project_devices (
    project_id int NOT NULL,
    device_id text NOT NULL,
    device_type text NOT NULL,
    start_time timestamptz NOT NULL,
    stop_time timestamptz,
    location geometry(Point, 4326),
    notes text,

    PRIMARY KEY (project_id, device_id),
    FOREIGN KEY (project_id) REFERENCES project(project_id),
    FOREIGN KEY (device_id) REFERENCES device(device_id)
  );
  CREATE INDEX IF NOT EXISTS project_devices_project_id_start_time_stop_time_idx ON project_devices (project_id, start_time DESC, stop_time DESC);

  --
  -- LoRaWAN meta-data for data that was transported by LoRaWAN
  --
  CREATE TABLE IF NOT EXISTS lorawan (
    ts timestamptz NOT NULL,
    device_id text NOT NULL,
    dr int4 NOT NULL,
    f_cnt int4 NOT NULL,
    f_port int4 NOT NULL,
    channel int4,
    rssi int4 NOT NULL,
    snr float4,
    rxinfo jsonb NOT NULL,
    txinfo jsonb NOT NULL,
    bat_v float4,

    PRIMARY KEY (device_id, ts)
  );
  CREATE INDEX IF NOT EXISTS lorawan_ts_idx ON lorawan (ts DESC);
  SELECT create_hypertable('lorawan', by_range('ts'), if_not_exists => TRUE);

  --
  -- Store measured soil moisture
  --
  CREATE TABLE IF NOT EXISTS soil_moisture (
    ts timestamptz NOT NULL,
    device_id text NOT NULL,
    depth_cm float NOT NULL,
    vwc float NOT NULL,
    ec_us_cm float,

    PRIMARY KEY (device_id, depth_cm, ts)
  );
  CREATE INDEX IF NOT EXISTS soil_moisture_ts_idx ON soil_moisture (ts DESC);
  CREATE INDEX IF NOT EXISTS soil_moisture_device_id_idx ON soil_moisture (device_id, ts DESC);
  SELECT create_hypertable('soil_moisture', by_range('ts'), if_not_exists => TRUE);

  --
  -- Store measured soil temperatures
  --
  CREATE TABLE IF NOT EXISTS soil_temp (
    ts timestamptz NOT NULL,
    device_id text NOT NULL,
    depth_cm float NOT NULL,
    temp_c float NOT NULL,

    PRIMARY KEY (device_id, depth_cm, ts)
  );
  CREATE INDEX IF NOT EXISTS soil_temp_ts_index ON soil_temp (ts DESC);
  CREATE INDEX IF NOT EXISTS soil_temp_device_id_ts_idx ON soil_temp (device_id, ts DESC);
  SELECT create_hypertable('soil_temp', by_range('ts'), if_not_exists => TRUE);

  --
  -- Store position data from a GPS
  --
  CREATE TABLE IF NOT EXISTS position (
    ts timestamptz NOT NULL,
    device_id text NOT NULL,
    location geometry(Point, 4326) NOT NULL,
    altitude_m float4,
    heading_deg float4,
    speed_m_s float4,

    PRIMARY KEY (device_id, ts)
  );
  CREATE INDEX IF NOT EXISTS position_ts_idx ON position (ts DESC);
  CREATE INDEX IF NOT EXISTS position_device_id_ts_idx ON position (device_id, ts DESC);
  SELECT create_hypertable('position', by_range('ts'), if_not_exists => TRUE);
EOSQL
