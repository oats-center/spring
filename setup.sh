#!/bin/bash

# Services that this script is can deploy
declare -A services
# Secrets made during the script
declare -A secrets

# FIXME: Make services setup their own DB ... Will need for not Self-host
# FIXME: If we are doing non-rootful containers, should be check to make sure the user's systemd session is in linger mode?

# FIXME: I should be using this I think??
quadlet_dir="$HOME/.config/containers/systemd"

# Define Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color 
BOLD='\e[1m'
NOBOLD='\e[22m'

ask_yes_no() {
    local prompt=$1
    local default=$2
    local options='[yn]';

    if [ "$default" == "y" ]; then
        options=['Yn'];
    elif [ "$default" == "n" ]; then
        options=['yN'];
    fi

    while true; do
        read -r -p "$(echo -e "${CYAN}$prompt ${YELLOW}$options${NC}: ")" yn
        if [ -z "$yn" ]; then
            yn=$default
        fi

        case $yn in
            [Yy] ) return 0;;
            [Nn] ) return 1;;
            * ) echo -e "${RED}Please answer yes (y) or no (n).${NC}";;
        esac
    done
}

generate_secret() {
    local length=${1:?}
    base64 --wrap=0 /dev/urandom | head -c$length
}

install_service() {
    local service=${1:?}
    local extra=$2

    if ! ask_yes_no "Self-host ${BOLD}$service${NOBOLD}? $extra" "y"; then
        return 1
    fi 

    mkdir -p "$quadlet_dir"
    path="$quadlet_dir/spring_$service"

    # Check if services has already been installed
    if [ -d $path ]; then
        echo -e "  ${RED}${BOLD}$service${NOBOLD} is already installed.${NC}"

        if ! ask_yes_no "  Would you like to delete ${BOLD}$service${NOBOLD} and reinstall? (WARNING: this will override manual changes)" "n"; then
            return 0
        fi

        rm -rf $path
    fi 

    cp -r "quadlet/$service" $path
    echo -e "  ${GREEN}Installed ${BOLD}$service${NOBOLD}${NC}"

    return 0
}

pull_containers() {
    local service=${1:?}

    mapfile -t images < <(sed -n 's/^Image=//p' "$quadlet_dir/spring_$service/"*.container)

    for image in ${images[@]}; do

        podman image exists $image

        if [ -z $? ]; then
            echo -e "    Fetching image: ${GREEN}${BOLD}$image${NOBOLD}${NC}"

            result=$(podman pull $image 2>&1)

            if [ $? -ne 0 ]; then
                echo -e "  ${RED}${BOLD}Image pull failed!${NOBOLD}${NC}. Error:"
                echo -e "${YELLOW}$result${NC}"
                echo -e "  ${RED}Exiting${NC}"
                exit 1;
            fi
        fi
    done

}

create_secret() {
    local secret=${1:?}
    local value=$2

    echo -e "  ${GREEN}Creating secret ${BOLD}$secret${NOBOLD}${NC}"

    if podman secret exists $secret; then
        echo -e "    ${RED}${BOLD}$secret${NOBOLD}  already exists.${NC}"

        if ! ask_yes_no "    Would you like to recreate it?" "n"; then
           return 0 
        fi

        result=$(podman secret rm $secret 2>&1)

        if [ $? -ne 0 ]; then
            echo -e "    ${RED}${BOLD}Podman secret removal failed!${NOBOLD}${NC}. Error:"
            echo -e "    ${YELLOW}$result${NC}"
            echo -e "    ${RED}Exiting${NC}"
            exit 1;
        fi
    fi

    if [ -z "$value" ]; then 
        read -r -p "$(echo -e "    ${CYAN}Enter value for ${secret}:${NC} ")" value
    fi

    result=$(echo -n $value | podman secret create $secret - 2>&1)

    if [ $? -ne 0 ]; then
        echo -e "    ${RED}${BOLD}Podman secret creation failed!${NOBOLD}${NC}. Error:"
        echo -e "    ${YELLOW}$result${NC}"
        echo -e "    ${RED}Exiting${NC}"
        exit 1;
    fi

    echo -e "    ${GREEN}Created secret ${BOLD}$secret${NOBOLD}${NC}"
    secrets[$secret]=$value
}

get_transformer_docs() {
    local transformerPath=${1:?}
    local lines=""
    local cnt=0;

    # Read the docs from the top of the transformer file, remove white spaces, and wrap into one line separated by ". "
    while IFS= read -r line; do
        if [[ "$line" == "#"* ]]; then

            line=$(echo $line | sed -e 's/^[#|[:space:]]*//')

            if [ -n "$line" ]; then
                if [ $cnt -gt 0 ]; then
                    echo -n ". "
                fi
                echo -n "$line"
                cnt+=1
            fi
        else
            break
        fi
    done < $transformerPath
}

echo -e "                 ${PURPLE}┌───────────────────────────────┐${NC}";
echo -e "                 ${PURPLE}│   ____            _           │${NC}";
echo -e "                 ${PURPLE}│  / __/___   ____ (_)___  ___ _│${NC}";
echo -e "                 ${PURPLE}│ _\ \ / _ \ / __// // _ \/ _ \`/│${NC}";
echo -e "                 ${PURPLE}│/___// .__//_/  /_//_//_/\_, / │${NC}";
echo -e "                 ${PURPLE}│    /_/                 /___/  │${NC}";
echo -e "                 ${PURPLE}└───────────────────────────────┘${NC}";
echo -e "                           ${PURPLE}${BOLD}Data Pipeline${NOBOLD}${NC}";
echo -e "                               ${YELLOW}- by -${NC}";
echo -e "             ${WHITE}${BOLD}The Open Ag Technology and Systems Center${NC}";
echo -e "                          ${WHITE}${BOLD}(oatscenter.org)${NOBOLD}${NC}";
echo -e "                                ${YELLOW}and${NC}";
echo -e "                              ${GREEN}${BOLD}IoT4Ag${NOBOLD}${NC}";
echo -e "                           ${GREEN}${BOLD}(iot4ag.us)${NOBOLD}${NC}";
echo
echo

echo -e "The SPRING data pipeline is made of up 100% open source software."
echo -e "All of which can be self-hosted for free on your own server or cloud virtual machine."
echo -e "However, most of the software componets do have paid commerically managed service offerings which can be used instead."
echo -e "In you intend to use a non-self hosted option for a service, then say \"no\" below and update the various confiugrations to connect to the managed version of the software."
echo

if ! command -v "systemctl" &> /dev/null; then
    echo -e "${RED}${BOLD}Systemd${NOBOLD} is required. Please try again on a systemd based Linux!${NC}"
    exit 1
fi

if ! command -v "podman" &> /dev/null; then
    echo -e "${RED}${BOLD}Podman${NOBOLD} is required. Please install (https://podman.io/docs/installation) and try again.${NC}"
    exit 1
fi

if [ ! -u /usr/bin/newuidmap ] || [ ! -u /usr/bin/newgidmap ]; then
    echo -e "${YELLOW}SUID bit is not set on /usr/bin/newuidmap or /usr/bin/newgidmap.${NC}"
    if ask_yes_no "Would you like to fix this now (requires sudo)?" "y"; then
        sudo chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap
        echo -e "${GREEN}SUID bits applied.${NC}"
    else
        echo -e "${RED}Rootless containers may not work correctly without this. Exiting.${NC}"
        exit 1
    fi
fi

###
### SPRING
###
if install_service "spring" "Establish SPRING environment (REQUIRED)"; then
    services["SPRING"]="spring"
    pull_containers "spring"
fi

###
### Chirpstack
###
if install_service "chirpstack" "LoRAWAN (manages sensor network)"; then
    services["Chirpstack"]="chirpstack-pod"

    pull_containers "chirpstack"

    create_secret "chirpstack_secret" $(generate_secret 32)
fi

###
### TimescaleDB
###
if install_service "tsdb" "TimescaleDB (data storage)"; then
    services["TimescaleDB"]="tsdb"

    pull_containers "tsdb"

    create_secret "tsdb_passwd"
    create_secret "tsdb_data_passwd"
    create_secret "tsdb_chirpstack_passwd"
fi

###
### NATS
###
if install_service "nats" "NATS (data connectivity)"; then
    services["NATS"]="nats"

    pull_containers "nats"

    create_secret "nats_admin_passwd"
    create_secret "nats_chirpstack_passwd"
fi

###
### Grafana
###
if install_service "grafana" "Grafana (data dashboarding)"; then
    services["Grafana"]="grafana"
    pull_containers "grafana"

    create_secret "grafana_admin_passwd"
fi

###
### Redpanda Connect
###
if install_service "rpc" "Redpanda Connect (data transformer)"; then
    pull_containers "rpc"

    for transformerPath in "transformers/"*; do
        if [ -f "$transformerPath" ]; then
            transformer=$(basename $transformerPath .yaml)
            docs=$(get_transformer_docs $transformerPath)

            if ask_yes_no "  Start the ${BOLD}$transformer${NOBOLD} transformer? ($docs)" "y"; then
                mkdir -p "$quadlet_dir/spring_rpc/transformers/"
                cp $transformerPath "$quadlet_dir/spring_rpc/transformers"

                services["Redpanda Connect - $transformer"]="rpc@$transformer"
            fi 
        fi
    done
fi

if ask_yes_no "Start the SPRING services now?" "y"; then
    echo -e "  ${GREEN}Reloading systemd${NC}"
    systemctl --user daemon-reload

    for service in "${!services[@]}"; do
        echo -e "  ${GREEN}Starting ${BOLD}${services[$service]} ($service)${NOBOLD}${NC}"
        systemctl --user start ${services[$service]}
    done
fi

echo -e "${PURPLE}==================================================${NC}"
echo -e "${PURPLE}            Created SPRING Pipeline!              ${NC}"
echo -e "${PURPLE}==================================================${NC}"

if ! [ ${#secrets[@]} -eq 0 ]; then
    echo -e "${YELLOW}You created the following secrets. Please store these credentials securely. You will need them!${NC}"
    echo

    printf "%-30s | %s\n" "Secret Name" "Value"
    printf "%-30s | %s\n" "------------------------------" "------------------------------------------"
    for secret_key in "${!secrets[@]}"; do
        printf "%-30s | ${GREEN}%s${NC}\n" "$secret_key" "${secrets[$secret_key]}"
    done
fi

echo
echo -e "${GREEN}You can access:${NC}"
echo -e "${GREEN}  Chirpstack: http://localhost:8080${NC}"
echo -e "${GREEN}  Grafana: http://localhost:3000${NC}"
