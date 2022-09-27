#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script brings up a Hyperledger Fabric network for testing smart contracts
# and applications. The test network consists of two organizations with one
# client each, and a single node Raft ordering service. Users can also use this
# script to create a channel deploy a chaincode on the channel

# the absolute path where this file is
export ROOT="$(dirname "$(realpath "$BASH_SOURCE")")"
# prepending $ROOT/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
export PATH="$ROOT/../bin":$PATH
export VERBOSE=false

set -e
# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform, e.g., darwin-amd64 or linux-amd64
OS_ARCH=$(echo "$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')

# avoid docker-compose warning about orphan containers
export COMPOSE_IGNORE_ORPHANS=True

# contains model-specific configurations and variables
source "$ROOT/globalParams.sh"
exportNetworkParams

# Print the usage message
# TODO: print an informative help message
function printHelp() {
  echo "Usage: ./network.sh [OPTS] MODE"
  echo "MODE:"
  echo "      up    executes the whole network from a clean start, including channels"
  echo "    down    tears down the network as configured"
  echo "OPTS (global defaults are defined in globalParams.sh:"
  echo "  -d <n>    retry failed commands every n seconds"
  echo "  -h        print this help message"
  echo "  -l <n>    set verbosity: 1->error,2->warning,3->info,4->debug,5->trace"
  echo "  -r <n>    retry failed commands n times before giving up"
  echo "  -v        verbose output: same as -l 4"
  echo
}

function checkOrLaunchSetup () {
  # retrieve the 'configParams.sh' script for every node and export its global variables
  IFS=$'\n'
  for PARAMS_FILE in $(listConfigParams)
  do
    source "$PARAMS_FILE"
    exportGlobalParams
    # check whether the setup was already executed
    # TODO: find a better way to tell whether the setup is complete or not
    if [ ! -r "$BASE_DIR/ca-server/tls-cert.pem" ]
    then
      exportOrgParams
      # if [ ! -x "$ORG_SETUP_SCRIPT" ]
      # then
      #   echo "$ORG_SETUP_SCRIPT not executable"
      #   exit 1
      # fi
      # execute the setup script
      "$ORG_SETUP_SCRIPT"
      STATUS=$?
      if [ ! $STATUS -eq 0 ];
        then
        [ $LOG_LEVEL -ge 2 ] && echo "setup script failed with exit status $STATUS: $ORG_SETUP_SCRIPT"
        exit 1
      fi
    fi
  done
}

# Generate orderer (system channel) genesis block.
function createGenesisBlock() {
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "Generate Orderer Genesis block"
  [ $LOG_LEVEL -ge 3 ] && echo
  # skip genesis block creation if it already exists
  if [ -f "$ROOT/system-genesis-block/genesis.block" ]
  then
    [ $LOG_LEVEL -ge 2 ] && echo "genesis block already exists, skipping creation..."
    return
  fi
  # Note: For some unknown reason (at least for now) the block file can't be
  # named orderer.genesis.block or the orderer will fail to launch!
  [ $LOG_LEVEL -ge 5 ] && set -x
  configtxgen -profile "$GENESIS_PROFILE" -channelID 'syschannel'\
    -outputBlock "$ROOT/system-genesis-block/genesis.block"\
    -configPath "$ROOT/configtx/" &> log.txt
  res=$?
  [ $LOG_LEVEL -ge 5 ] && set +x
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
  if [ $res -ne 0 ]; then
    echo $'\e[1;32m'"Failed to generate orderer genesis block..."$'\e[0m'
    exit 1
  fi
}

# After we create the org crypto material and the system channel genesis block,
# we can now bring up the clients and orderering service. By default, the base
# file for creating the network is "docker-compose-test-net.yaml" in the ``docker``
# folder. This file defines the environment variables and file mounts that
# point the crypto material and genesis block that were created in earlier.

# Bring up the client and orderer nodes using docker compose.
function networkUp {
  checkOrLaunchSetup && createGenesisBlock
}

function orgsUp () {
  # find all the 'configParams.sh' scripts in the subtree and export their global variables
  IFS=$'\n'
  for PARAMS_FILE in $(listConfigParams)
  do
    source "$PARAMS_FILE"
    exportOrgParams
    # if [ ! -x "$ORG_UP_SCRIPT" ]
    # then
    #   echo "$ORG_UP_SCRIPT not executable"
    #   exit 1
    # fi
    # bring up the organization
    "$ORG_UP_SCRIPT"
    STATUS=$?
    if [ ! $STATUS -eq 0 ];
      then
      [ $LOG_LEVEL -ge 2 ] && echo "orgUp script failed with exit status $STATUS: $ORG_UP_SCRIPT"
      exit 1
    fi
  done
}

## call the script to join create the channel and join the clients of org1 and org2
function createChannels() {

  for ((I = 1; I <= "$NUM_CHANNELS"; I++))
  do
    # now run the script that creates a channel. This script uses configtxgen once
    # more to create the channel creation transaction and the anchor client updates.
    # configtx.yaml is mounted in the cli container, which allows us to use it to
    # create the channel artifacts
    CHANNEL_INDEX="$I"
    "$ROOT/scripts/createChannel.sh" "$CHANNEL_INDEX" "$VERBOSE"
    if [ $? -ne 0 ]; then
      echo "Error !!! Create channel number $CHANNEL_INDEX failed"
      exit 1
    fi
  done
}

function deployDefaultChaincode {
  source "$ROOT/chaincodeParams.sh"
  if [ $NUM_CHAINCODES -lt 1 ]; then
    echo "Warning ! test chaincode not defined"
  else
    "$ROOT/scripts/chaincode.sh" 'e2e'
    if [ $? -ne 0 ]; then
      echo "Error !!! Test chaincode deployment failed"
      exit 1
    fi
  fi
}

source "$ROOT/binaries.sh"

function up {
  [ $LOG_LEVEL -ge 2 ] && echo
  [ $LOG_LEVEL -ge 2 ] && echo '=================== LAUNCH NETWORK ======================'
  binariesMain && networkUp && orgsUp && createChannels && deployDefaultChaincode
  [ $LOG_LEVEL -ge 2 ] && echo '============ NETWORK LAUNCHED SUCCESSFULLY =============='
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# This function is called when you bring the network down
function removeUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-client.*/) {print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    [ $LOG_LEVEL -ge 4 ] && echo "---- No images available for deletion ----"
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

# Tear down running network
function networkDown() {
  [ $LOG_LEVEL -ge 2 ] && echo '============ CLEANUP NETWORK =============='
  [ $LOG_LEVEL -ge 2 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo 'Stop and delete containers alongside with their volumes'
  set +e
  IFS=$'\n'
  for PARAMS_FILE in $(listConfigParams)
  do
    source "$PARAMS_FILE"
    exportGlobalParams
    exportCaParams
    exportOrgParams
    [ $LOG_LEVEL -ge 3 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo "-> stop and delete CA containers: $CA_NAME"
    [ $LOG_LEVEL -ge 3 ] && echo
    [ $LOG_LEVEL -ge 5 ] && set -x
    IMAGE_TAG="$CA_IMAGETAG" docker-compose --log-level ERROR -f "$CA_COMPOSE_FILE" -p "$PROJECT_NAME"\
      exec "$CA_NAME" 'rm -rf /etc/hyperledger/fabric-ca-server/*' 2>log.txt
    IMAGE_TAG="$CA_IMAGETAG" docker-compose --log-level ERROR -f "$CA_COMPOSE_FILE" -p "$PROJECT_NAME"\
      down --volumes 2>>log.txt
    [ $LOG_LEVEL -ge 4 ] && cat log.txt
    rm -f "$CA_COMPOSE_FILE"
    for ((I=1; I <= NODE_NUM; I++))
    do
      exportNode"$I"Params
      [ $LOG_LEVEL -ge 3 ] && echo
      [ $LOG_LEVEL -ge 3 ] && echo "-> stop and delete node containers: $NODE_FULL_NAME"
      [ $LOG_LEVEL -ge 3 ] && echo
      IMAGE_TAG="$NODE_IMAGETAG" docker-compose --log-level ERROR -f "$NODE_COMPOSE_FILE" -p "$PROJECT_NAME"\
        down --volumes 2>log.txt
      [ $LOG_LEVEL -ge 4 ] && cat log.txt
      rm -f "$NODE_COMPOSE_FILE"
      #TODO find cleaner solution: workaround volume not removed
      docker volume rm -f "$NODE_FULL_NAME"
    done
    ## remove fabric ca artifacts -- client config files are kept since they are different from defaults
    rm -rf "$BASE_DIR/ca-server" "$BASE_DIR/users" "$BASE_DIR/orderers" "$BASE_DIR/clients" "$BASE_DIR/tlsca"
    [ $LOG_LEVEL -ge 5 ] && set +x
  done
  # Don't remove the generated artifacts -- note, the ledgers are always removed
  removeUnwantedImages
  # remove orderer block and other channel configuration transactions and certs
  rm -rf "$ROOT/system-genesis-block"/*.block

  # remove channel and script artifacts
  rm -rf "$ROOT/channel-artifacts" "$ROOT/log.txt"
  set -e
}

# Parse commandline args

## Parse mode
if [[ $# -lt 1 ]] ; then
  printHelp
  exit 0
fi

# parse input flags
while [[ $# -ge 1 ]] ; do
  key="$1"
  case $key in
  -h)
    printHelp
    exit 0
    ;;
  -r)
    export MAX_RETRY="$2"
    shift
    ;;
  -d)
    export CLI_DELAY="$2"
    shift
    ;;
  -v)
    export LOG_LEVEL='4' # debug
    shift
    ;;
  -l)
    export LOG_LEVEL="$2" # from 1=error to 5=trace
    shift
    ;;
  up|down)
    MODE="$1"
    break
    ;;
  * )
    echo
    echo "Unknown flag: $key"
    echo
    printHelp
    exit 1
    ;;
  esac
  shift
done

# Determine mode of operation and printing out what we asked for
# TODO improve log messages
if [ "$MODE" == "up" ]; then
  echo
  echo "Cleanup and launch the entire network, including the creation and join of channels"
  echo
  networkDown
  up
elif [ "$MODE" == "down" ]; then
  echo
  echo "Stopping network"
  echo
  networkDown
else
  printHelp
  exit 1
fi
set +e
