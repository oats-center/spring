# Software versions

- TimescaleDB: Postgres 17.4, TimescaleDB 2.19
- Chirpstack: 4.12
  - Redis: 8.0.0
  - Mosquitto: 2.0.21
- NATS: 2.11.3
- Redpanda Connect: 24.1.21
- Grafana: 12.0.0

# Install podman

SPRING's data pipeline expects to run on a Systemd based Linux with Podman installed. Most modern Linux distributions offer these tools.
Likely Systemd is already part of your host, but you may need to install Podman.
A useful guide can be found here: (https://podman.io/docs/installation)[https://podman.io/docs/installation]

# Install the SPRING data pipeline

We have created a simple installed install called `setup.sh`.
The pipeline does not require rootful containers, and by default they are installed to run as the current user.
However, to ensure the services start at boot time, you should make your user systemd session "linger".
`setup.sh` will check for and enable it, however you are require to have sudo access.

To install:

```
git clone https://github.com/oats-center/spring
cd pipeline
bash setup.sh
```

And complete the question and answer prompts.

# Manual installation

## Quadlet

The SPRING data pipeline uses Podman Quadlet and systemd to manage the software components, configuration, and lifetimes.
You can manual install the pipeline by copying the contents of the `quadlet` folder into your preferred quadlet path (often `/etc/containers/systemd` for rootful and `$HOME/.config/containers/systemd` for non-rootful)
Once copied, reload the systemd deamon (`systemctl daemon-reload` or `systemctl --user daemon-reload`)

## Secrets

There are a variety of secrets which need to created for the containers to start properly.

One way to create a Podman secret is with:

```sh
printf "<secret-value>" | podman secret create <secret_name> -
```

Here is a list of required secrets:

| Service     | Secret Name            | Description                                                                                                                                          |
| ----------- | ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| TimescaleDB | tsdb_passwd            | The password for the `postgres` account (admin). Used to extend, restore, backup, or do other maintenance of the database                            |
| TimescaleDB | tsdb_data_passwd       | The password for the `data` account. Used to store all collected sensor data                                                                         |
| TimescaleDB | tsdb_chirpstack_passwd | The password for the `chirpstack` account. Used by the Chirpstack to store state, gateway information, and other sensor details.                     |
| Chirpstack  | chirpstack_secret      | A 32 character long random string. Used as a hash value for the Chirpstack UI (Hint: `openssl rand -base64 32`)                                      |
| NATS        | nats_admin_passwd      | Admin account password used to manage NATS, create users, streams, etc.                                                                              |
| NATS        | nats_chirpstack_passwd | Account password for all communication between Chirpstack and LoRaWAN gateways. You will need to give this password to all gateways in your network. |
| Grafana     | grafana_admin_passwd   | The main Grafana account password that will be used to access and plot sensor data.                                                                  |

## Starting services

All installed services should automatically start on boot (unless you have manual stopped the service prior the reboot).
To start them initally:

```sh
systemctl start tsdb nats chirpstack-pod grafana
```

## Starting transformers

Redpanda connect needs to be started for each sensor type that your SPRING will process.
The transformers are stored in `/rpc/transformers` and are generally named by the sensor make and model.
You can start a specific transformer with:

```sh
systemctl start rpc@<transformer-file-name>
```

Where `transformer-file-name` is the file name in the `/rpc/transformers` folder.
For example `systemctl start rpc@lse01` would start the transformer defined in `/rpc/transformers/lse01.yaml`.

## Done!

That's it.
You should have a working SPRING backend.
Go ahead and add your gateways and sensors to Chirpstack to start the data flow.

# Connecting to TimescaleDB

The admin user for Postgres is `postgres`. The default database is called `postgres`. You can connect to the database with:

```sh
podman exec -it tsdb psql -U postgres
```

# Connecting to Chirpstack UI

Chirpstack is managed through a web user interface. It is available on port "8080". In a web browser, connect to this website: `http://<server-ip>:8080`

The admin username is `admin` and the default password is `admin`. We strongly recommend that you use the web ui to change the admin password, particularly if your server is internet accessible.

# Connection to Grafana

Grafana is a web application running on your server. In a web browser, connect to this website `http://<server-ip>:3000`.

The default username is `admin` and the password is what you defined when creating the `grafana_admin_passwd` secret.
