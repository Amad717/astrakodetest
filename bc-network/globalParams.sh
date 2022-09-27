#!/bin/bash

### CONFIGURABLE OPTIONS ###
# the following options are default values that can be overwritten via network.sh cli options
# number of retries on an unsuccessful command
export MAX_RETRY='10'
# delay between command retries, in seconds
export CLI_DELAY='2'
# level of logs verbosity, represented by an integer
export LOG_LEVEL="${LOG_LEVEL:-4}" # 1->error, 2->warning, 3->info, 4->debug, 5->trace
############################
# map of our log levels (1-5) against the ones for fabric and docker-compose
export FABRIC_LOGS=('' 'critical' 'error' 'warning' 'info' 'debug')
export COMPOSE_LOGS=('' 'CRITICAL' 'ERROR' 'WARNING' 'INFO' 'DEBUG')

ROOT="$(dirname "$(realpath "$BASH_SOURCE")")"

listConfigParams () {
  local all='false'
  if [ "$#" -eq 2 ]; then
    local type="$1"
    local name="$2"
    echo "$ROOT/organizations/$type/$name/configParams.sh"
  elif [ "$#" -eq 1 ]; then
    # list all organizations of the given type if no name is specified
    local type="$1"
    for org in $(ls "$ROOT/organizations/$type"); do
      echo "$ROOT/organizations/$type/$org/configParams.sh"
    done
  elif [ "$#" -eq 0 ]; then
    # list all organizations if none is specified
    for type in 'client' 'order'; do
      listConfigParams $type
    done
  else
    echo "expected usage: listConfigParams [ <client|order> [ORG_NAME] ]"
    exit 1
  fi
}

### test per silvia ###
exportNetworkParams () {
  # genesis profile
  export GENESIS_PROFILE="TwoOrgsOrdererGenesis"
  # default image tag
  export IMAGETAG="2.2.0"
  # default ca image tag
  export CA_IMAGETAG="1.4.7"
  # default database
  export DATABASE="leveldb"
  # number of channels in this network
  export NUM_CHANNELS='1'
}

exportChannel1Params () {
	export CHANNEL_NAME='diamondchannell'
	export CHANNEL_PROFILE='diamondchannellProfile'
	# full name of the organization that creates the channel
	export CHANNEL_CREATOR='Planner'

	# information about the orderer that should validate channel creation
	local CHANNEL_ORDERER_ORG='orderer'
	local CHANNEL_ORDERER_NAME='ordernode'
	source "$(listConfigParams 'order' "$CHANNEL_ORDERER_ORG")"
	local ORD_INDEX=$(getNodeIndex "$CHANNEL_ORDERER_NAME")
	exportNode"$ORD_INDEX"Params
	export ORDERER_CA="$NODE_PATH/msp/tlscacerts/tlsca.orderer-cert.pem"
	export CHANNEL_ORDERER="$CHANNEL_ORDERER_NAME.$CHANNEL_ORDERER_ORG"
	export ORDERER_HOST='localhost'
	export ORDERER_PORT='6052'

	# list of (anchor) nodes that should join the channel, each split into NODE_NAME and ORG_NAME
	
	export CHANNEL_MEMBER1_NODE='firstpeerplanner'
	export CHANNEL_MEMBER1_ORG='Planner'
	


	export NUM_MEMBERS='1'
	export NUM_ANCHORS='0'
	
	export CHANNEL_SIZE='3'


	export CHANNEL_ORGS=(Planner )
	
	
	
	export CHANNEL_ORG0_NODES=(firstpeerplanner)
	
	
	
	
    
   
}

