BASE_DIR="$(dirname "$(realpath "$BASH_SOURCE")")"
ORG_NAME="orderer"

### CONFIGURABLE OPTIONS ###
### The following options overwrite their defaults for this organization only
### Defaults are defined in globalParams.sh or via network.sh cli option:
## number of retries on an unsuccessful command
#export MAX_RETRY='10'
## delay between command retries, in seconds
#export CLI_DELAY='2'
## level of logs verbosity, represented by an integer
#export LOG_LEVEL='3' # 1->error, 2->warning, 3->info, 4->debug, 5->trace
# map of our log levels against fabric's
export FABRIC_LOGS=('fatal' 'critical' 'error' 'warning' 'info' 'debug')
############################
# map of our log levels (1-5) against the ones for  fabric and docker-compose
export FABRIC_LOGS=('' 'critical' 'error' 'warning' 'info' 'debug')
export COMPOSE_LOGS=('' 'CRITICAL' 'ERROR' 'WARNING' 'INFO' 'DEBUG')

# space-separated list of organization nodes, starting from index 1
MEMBERS=('' 'ordernode' 'ordernode')

function getNodeIndex {
  NAME=$1
  for i in "${!MEMBERS[@]}"
  do
    if [[ "${MEMBERS[$i]}" = "$NAME" ]]; then
      echo "$i";
      exit
    fi
  done
  echo "Node not found: $NAME"
  exit 1
}

function exportGlobalParams {

  export PROJECT_NAME="test"
  export BASE_DIR="$BASE_DIR"

}

function exportOrgParams {

  export NODE_NUM="2"
  export MSP_NAME="orderer"
  export ORG_SETUP_SCRIPT="$BASE_DIR/setupOrdererOrg.sh"
  export ORG_UP_SCRIPT="$BASE_DIR/orderersUp.sh"

}

function exportCaParams {

  export CA_NAME="orderca"
  export CA_HOST="localhost"
  export CA_PORT="6051"
  export CA_IMAGETAG="1.4.7"
  export CA_COMPOSE_FILE="$BASE_DIR/docker/$CA_NAME-compose.yaml"

}

function exportNode1Params {

  local NODE_INDEX=1
  export NODE_NAME="${MEMBERS[NODE_INDEX]}"
  export NODE_FULL_NAME="$NODE_NAME.$ORG_NAME"
  export NODE_HOST="localhost"
  export NODE_IMAGETAG="2.2.0"
  export NODE_PORT="6052"
  export NODE_COMPOSE_FILE="$BASE_DIR/docker/node_$NODE_INDEX-compose.yaml"
  export NODE_PATH="$BASE_DIR/orderers/node_$NODE_INDEX"

}

function exportNode2Params {

  local NODE_INDEX=2
  export NODE_NAME="${MEMBERS[NODE_INDEX]}"
  export NODE_FULL_NAME="$NODE_NAME.$ORG_NAME"
  export NODE_HOST="localhost"
  export NODE_IMAGETAG="2.2.0"
  export NODE_PORT="6052"
  export NODE_COMPOSE_FILE="$BASE_DIR/docker/node_$NODE_INDEX-compose.yaml"
  export NODE_PATH="$BASE_DIR/orderers/node_$NODE_INDEX"

}