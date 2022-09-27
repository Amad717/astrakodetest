#!/bin/bash

# Set environment variables for the client org
setGlobals() {
  if [ "$#" -eq 2 ]
  then
    local ORG="$1"
    local NODE="$2"
    CONFIG_PARAMS=$(listConfigParams 'client' "$ORG")
    source "$CONFIG_PARAMS"
    exportGlobalParams
    exportOrgParams
    local NODE_INDEX="$(getNodeIndex $NODE)"
  else
    echo "expected usage: setGlobals ORG_NAME NODE_NAME"
    exit 1
  fi
  [ $LOG_LEVEL -ge 5 ] && echo "Export global params for $NODE.$ORG"
  exportNode"$NODE_INDEX"Params
  export CORE_PEER_TLS_ROOTCERT_FILE="$NODE_PATH/$CLIENT_CA_relpath"
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_ADDRESS="$NODE_HOST:$NODE_PORT"
  export CORE_PEER_LOCALMSPID="$MSP_NAME"
  export CORE_PEER_MSPCONFIGPATH="$BASE_DIR/users/Admin@$ORG_NAME/msp"
  export FABRIC_LOGGING_SPEC="${FABRIC_LOGS[$LOG_LEVEL]}"
  export FABRIC_CFG_PATH="$ROOT/../config/"
  [ $LOG_LEVEL -ge 5 ] && env | grep CORE
}

packageChaincode() {
  # this could be done by a single orgainization if they are able/willing to share the generated package
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "peer chaincode package"
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 4 ] && set -x
  if [ ! -f "$CC_PKG_NAME" ]; then
    peer lifecycle chaincode package "$CC_PKG_NAME" --path "$CC_SRC_PATH" --lang "$CC_LANG"\
    --label "$CC_LABEL"
  fi
  if [ $? != 0 ]; then
    echo "chaincode packaging failed"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && set +x
}

# takes orgName nodeName as inputs, correct value for CC_PKG_NAME must be defined beforehand
installChaincode() {
  local _ORG="$1"
  local _NODE="$2"
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "peer chaincode install on $_NODE.$_ORG"
  [ $LOG_LEVEL -ge 3 ] && echo

  setGlobals "$_ORG" "$_NODE"

  # add $NODE_HOST:$NODE_PORT to ARRAY_NODE_ADDRESSES
  ARRAY_NODE_ADDRESSES+=("$CORE_PEER_ADDRESS")
  # add CORE_PEER_TLS_ROOTCERT_FILE to ARRAY_TLS_ROOTCERTS
  ARRAY_TLS_ROOTCERTS+=("$CORE_PEER_TLS_ROOTCERT_FILE")
  
  [ $LOG_LEVEL -ge 4 ] && set -x
  if [ -f "$CC_PKG_NAME" ]; then
    peer lifecycle chaincode install "$CC_PKG_NAME"
    if [ $? != 0 ]; then
      echo "chaincode installation failed"
      cat log.txt
      exit 1
    fi
  else
    echo "ERROR: chaincode package not found"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && set +x
}

approveChaincode() {
  peer lifecycle chaincode approveformyorg --orderer "$ORDERER_HOST:$ORDERER_PORT" --tls  --cafile "$ORDERER_CA"\
      --sequence "$CC_SEQUENCE" --channelID "$CHANNEL_NAME" --name "$CC_NAME" --version "$CC_VERSION" \
      --package-id "$PACKAGE_ID" $([ "$INIT_REQUIRED" == 'true' ] && echo '--init-required') &> log.txt
  if [ $? != 0 ]; then
    echo "chaincode org approval failed"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
}

checkCommitReadiness() {
  echo
  echo "peer lifecycle chaincode checkcommitreadiness"
  echo
  peer lifecycle chaincode checkcommitreadiness --orderer "$ORDERER_HOST:$ORDERER_PORT" --channelID "$CHANNEL_NAME" --tls \
    --cafile "$ORDERER_CA" --name "$CC_NAME" --version "$CC_VERSION" --sequence "$CC_SEQUENCE" \
    $([ "$INIT_REQUIRED" == 'true' ] && echo '--init-required') &> log.txt
  if [ $? != 0 ]; then
    echo "chaincode check commit readiness failed"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
}

commitChaincode() {
  # shenanigans to handle commit command properly for MAJORITY endorsement
  # TO DO: check whether this is actually needed
  COMMIT_CMD="peer lifecycle chaincode commit --orderer $ORDERER_HOST:$ORDERER_PORT --channelID $CHANNEL_NAME --name $CC_NAME --version $CC_VERSION --sequence $CC_SEQUENCE --cafile $ORDERER_CA --tls"
  for x in "${!ARRAY_NODE_ADDRESSES[@]}"; do
    COMMIT_CMD+=" --peerAddresses ${ARRAY_NODE_ADDRESSES[x]}"
  done
  for y in "${!ARRAY_TLS_ROOTCERTS[@]}"; do
    COMMIT_CMD+=" --tlsRootCertFiles ${ARRAY_TLS_ROOTCERTS[y]}"
  done
  if [ "$INIT_REQUIRED" == 'true' ]; then
    COMMIT_CMD+=" --init-required"
  fi

  echo
  echo "peer lifecycle chaincode commit"
  echo

  [ $LOG_LEVEL -ge 4 ] && echo "$COMMIT_CMD"
  eval "$COMMIT_CMD"
  if [ $? != 0 ]; then
    echo "chaincode commit failed"
    exit 1
  fi
}

initChaincode() {
  # shenanigans to handle init command properly for MAJORITY endorsement
  # TO DO: check whether this is actually needed
  INIT_CMD="peer chaincode invoke --orderer $ORDERER_HOST:$ORDERER_PORT --tls --cafile $ORDERER_CA -C $CHANNEL_NAME --name $CC_NAME --isInit"
  for i in "${!ARRAY_NODE_ADDRESSES[@]}"; do
    INIT_CMD+=" --peerAddresses ${ARRAY_NODE_ADDRESSES[i]}"
  done
  for i in "${!ARRAY_TLS_ROOTCERTS[@]}"; do
    INIT_CMD+=" --tlsRootCertFiles ${ARRAY_TLS_ROOTCERTS[i]}"
  done
  if [ "$INIT_REQUIRED" == 'true' ]; then
    INIT_CMD+=" -c '{"\""function"\"":"\"""
    INIT_CMD+=$INIT_FUNCTION_NAME
    INIT_CMD+=""\"","\""Args"\"":[]}'"
  fi

  echo
  echo "chaincode initialization"
  echo
  
  [ $LOG_LEVEL -ge 4 ] && echo "$INIT_CMD"
  eval "$INIT_CMD"
  if [ $? != 0 ]; then
    echo "chaincode initialization failed"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
}

# chaincode deploy operations are briefly described in:
# https://medium.com/geekculture/how-to-deploy-chaincode-smart-contract-45c20650786a
deployCC() {

  # get chaincodeParams
  exportChaincode"$CC_INDEX"Params
  
  # construct cc label from chaincodeParams
  CC_LABEL="$CC_NAME-$CC_VERSION"

  # loop channels to install cc on every peer
  # TO DO: have array in chaincodeParams with all channels where CC needs to be deployed
  # OR get channel as input and handle each channel separately
  for i in "${!CHANNEL_LIST[@]}"; do

    # (re)instantiate helper arrays
    ARRAY_NODE_ADDRESSES=()
    ARRAY_TLS_ROOTCERTS=()

    # shenanigans to get right export name for this channel
    local CHANNEL_NAME="${CHANNEL_LIST[i]}"
    local GREP_ARGS="CHANNEL_NAME='$CHANNEL_NAME'"
    local LINE_NUM=$(grep -n "$GREP_ARGS" $ROOT/globalParams.sh)
    local LINE_NUM=$(cut -d ":" -f1 <<< $LINE_NUM)
    local LINE_NUM=$(($LINE_NUM - 1))
    local EXPORT_CMD=$(sed "${LINE_NUM}q;d" $ROOT/globalParams.sh)
    local EXPORT_CMD=$(cut -d " " -f1 <<< $EXPORT_CMD)
    eval "$EXPORT_CMD"
      
    # shenanigans to get orgs array
    local ARRAY_STR=$(grep CHANNEL"$((i+1))"_ORGS $ROOT/customChaincodeParams.sh)
    local ARRAY_STR=$(sed "${CC_INDEX}q;d" <<< $ARRAY_STR)
    local ARRAY_STR=$(cut -d "=" -f2 <<< $ARRAY_STR)
    local ARRAY_STR=$(cut -d "(" -f2 <<< $ARRAY_STR)
    local ARRAY_STR=$(cut -d ")" -f1 <<< $ARRAY_STR)
    local ORGS_HELPER_ARRAY=($ARRAY_STR)
   
    # loop channel orgs and install cc on relevant peers
    for j in "${!ORGS_HELPER_ARRAY[@]}"; do

      local ORG="${ORGS_HELPER_ARRAY[j]}"

      # we need this for chaincode package
      export FABRIC_CFG_PATH="$ROOT/../config/"

      # steps for lifecycle: package, install, approve, commit
      # do package only once per org
      packageChaincode
      
      # shenanigans to get org nodes array
      local ARRAY_STR=$(grep CHANNEL"$((i+1))"_ORG"$((j+1))"_NODES $ROOT/customChaincodeParams.sh)
      local ARRAY_STR=$(sed "${CC_INDEX}q;d" <<< $ARRAY_STR)
      local ARRAY_STR=$(cut -d "=" -f2 <<< $ARRAY_STR)
      local ARRAY_STR=$(cut -d "(" -f2 <<< $ARRAY_STR)
      local ARRAY_STR=$(cut -d ")" -f1 <<< $ARRAY_STR)
      local NODES_HELPER_ARRAY=($ARRAY_STR)
      
      ## loop through all org peers for installation
      for k in "${!NODES_HELPER_ARRAY[@]}"; do
        local NODE="${NODES_HELPER_ARRAY[k]}"
        # TO DO: check whether CC needs to be installed on this peer
        installChaincode $ORG $NODE
        # Check installation and get package ID
        for cc in $(peer lifecycle chaincode queryinstalled --output json | jq -c '.installed_chaincodes[]')
        do
          if [ $(echo "$cc" | jq '.label' | tr -d '"') == "$CC_LABEL" ]; then
            PACKAGE_ID=$(echo "$cc" | jq '.package_id' | tr -d '"')
            break
          fi
        done
      done

      # remove CC package
      rm "$CC_PKG_NAME"

      # approve CC for this ORG
      approveChaincode

      # If last org we can wrap up
      if [ $((j+1)) -eq "${#CHANNEL_ORGS[@]}" ]; then
        # check commit readiness
        checkCommitReadiness
        # commit
        commitChaincode
        # initialize if needed
        if [ "$INIT_REQUIRED" == 'true' ]; then
          initChaincode
        fi
      fi
    done
  done
}

readChannelName () {
  CHANNEL_LIST_STRING="${CHANNEL_LIST[*]}"
  echo "Choose on which channel to invoke the $CC_NAME chaincode"
  echo
  echo "Available choices: $CHANNEL_LIST_STRING"
  echo
  read -p "Enter channel name: " CHANNEL_NAME
  if [[ ! $CHANNEL_LIST_STRING == *"$CHANNEL_NAME"* ]]; then
    echo "Channel name invalid, please provide a valid name"
    echo
    readChannelName
  fi
}

readPeerName () {
  # get channel index
  for a in "${!CHANNEL_ORG_NODE_COUPLES[@]}"; do
    local TEMP_STR="${CHANNEL_ORG_NODE_COUPLES[a]}"
    local TEMP_STR=$(cut -d "," -f1 <<< $TEMP_STR)
    CHANNEL_ORG_NODE_COUPLES[$a]="$TEMP_STR"
  done
  PEER_LIST_STRING="${CHANNEL_ORG_NODE_COUPLES[*]}"
  echo
  echo "Choose on which peer to invoke the $CC_NAME chaincode"
  echo
  echo "Available choices: $PEER_LIST_STRING"
  echo
  read -p "Enter peer name: " PEER_NAME
  if [[ ! $PEER_LIST_STRING == *"$PEER_NAME"* ]]; then
    echo "Peer name invalid, please provide a valid name"
    echo
    readPeerName
  fi
  NODE="$PEER_NAME"
  exportChaincode"$CC_INDEX"Params
  for b in "${!CHANNEL_ORG_NODE_COUPLES[@]}"; do
    if [[ "${CHANNEL_ORG_NODE_COUPLES[b]}" == *"$PEER_NAME"* ]]; then
      local TEMP_STR="${CHANNEL_ORG_NODE_COUPLES[b]}"
      local TEMP_STR=$(cut -d "," -f2 <<< $TEMP_STR)
      ORG="$TEMP_STR"
    fi
  done
}

readEndorsers () {
  # get channel index
  for a in "${!CHANNEL_ORG_NODE_COUPLES[@]}"; do
    local TEMP_STR="${CHANNEL_ORG_NODE_COUPLES[a]}"
    local TEMP_STR=$(cut -d "," -f1 <<< $TEMP_STR)
    CHANNEL_ORG_NODE_COUPLES[$a]="$TEMP_STR"
    if [[ $TEMP_STR = $PEER_NAME ]]; then
      unset 'CHANNEL_ORG_NODE_COUPLES[a]'
    fi
  done
  ENDORSERS_LIST_STRING="${CHANNEL_ORG_NODE_COUPLES[*]}"
  echo
  echo "Choose which additional peers should endorse the transaction (by default the peer that invokes it already endorses it)"
  echo
  echo "Available choices: $ENDORSERS_LIST_STRING"
  echo
  read -p "Enter endorser(s) name(s), separated by a space: " ENDORSERS
  IFS=' ' read -r -a ENDORSERS_ARRAY <<< "$ENDORSERS"
  for a in "${!ENDORSERS_ARRAY[@]}"; do
    if [[ ! $ENDORSERS_LIST_STRING == *"${ENDORSERS_ARRAY[a]}"* ]]; then
      echo
      echo "${ENDORSERS_ARRAY[a]} is an invalid endorser, please provide valid endorsers"
      readEndorsers
    fi
  done
  echo
  echo "Chosen endorsers: ${ENDORSERS_ARRAY[*]}"
  echo
  read -p "Confirm endorsers? Enter y to confirm " CONFIRMATION
  if [[ ! $CONFIRMATION == "y" ]]; then
    echo
    echo "Endorsers unconfirmed, enter again"
    readEndorsers
  fi
  ENDORSERS_ADDRESSES=""
  ENDORSERS_CA_CERTS=""
  for a in "${!ENDORSERS_ARRAY[@]}"; do
    ENDORSER_NODE="${ENDORSERS_ARRAY[a]}"
    exportChaincode"$CC_INDEX"Params
    for b in "${!CHANNEL_ORG_NODE_COUPLES[@]}"; do
      if [[ "${CHANNEL_ORG_NODE_COUPLES[b]}" == *"$ENDORSER_NODE"* ]]; then
        local TEMP_STR="${CHANNEL_ORG_NODE_COUPLES[b]}"
        local TEMP_STR=$(cut -d "," -f2 <<< $TEMP_STR)
        ENDORSER_ORG="$TEMP_STR"
      fi
    done
    setGlobals "$ENDORSER_ORG" "$ENDORSER_NODE"
    ENDORSERS_ADDRESSES+=" --peerAddresses $CORE_PEER_ADDRESS"
    ENDORSERS_CA_CERTS+=" --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE"
  done
}

readFunctionName () {
  echo
  echo "Choose which function to invoke for the $CC_NAME chaincode"
  echo
  read -p "Enter function name: " FUNCTION_NAME
  echo
  echo "Entered function name: $FUNCTION_NAME"
  echo
  read -p "Confirm function name? Enter y to confirm " CONFIRMATION
  if [[ ! $CONFIRMATION == "y" ]]; then
    echo
    echo "Function name unconfirmed, enter again"
    readFunctionName
  fi
}

readArguments () {
  echo
  echo "Choose the arguments to provide for the selected $FUNCTION_NAME function"
  echo
  read -p "Enter all of the function's arguments, separated by a space: " ARGUMENTS
  IFS=' ' read -r -a ARGS_ARRAY <<< "$ARGUMENTS"
  echo
  echo "Entered arguments: ${ARGS_ARRAY[*]}"
  echo
  read -p "Confirm arguments? Enter y to confirm " CONFIRMATION
  if [[ ! $CONFIRMATION == "y" ]]; then
    echo
    echo "Arguments unconfirmed, enter again"
    readArguments
  fi
}

interactCC() {
  exportChaincode"$CC_INDEX"Params
  readChannelName
  # shenanigans to get right export name for this channel
  local GREP_ARGS="CHANNEL_NAME='$CHANNEL_NAME'"
  local LINE_NUM=$(grep -n "$GREP_ARGS" $ROOT/globalParams.sh)
  local LINE_NUM=$(cut -d ":" -f1 <<< $LINE_NUM)
  local LINE_NUM=$(($LINE_NUM - 1))
  local EXPORT_CMD=$(sed "${LINE_NUM}q;d" $ROOT/globalParams.sh)
  local EXPORT_CMD=$(cut -d " " -f1 <<< $EXPORT_CMD)
  eval "$EXPORT_CMD"
  readPeerName
  if [[ ! $MODE == "query" ]]; then
    readEndorsers
  fi
  setGlobals "$ORG" "$NODE"
  if [ -n "$ENDORSERS_ADDRESSES" ]; then
    ENDORSERS_ADDRESSES+=" --peerAddresses $CORE_PEER_ADDRESS"
    ENDORSERS_CA_CERTS+=" --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE"
  fi
  readFunctionName
  readArguments
  # Form -c properly
  local INVOKE_CMD='{"Args":['
  for a in "${!ARGS_ARRAY[@]}"; do
    INVOKE_CMD+='"'
    local TEMP_STR="${ARGS_ARRAY[a]}"
    INVOKE_CMD+=$TEMP_STR
    INVOKE_CMD+='"'
    if [ ! $((a+1)) -eq "${#ARGS_ARRAY[@]}" ]; then
      INVOKE_CMD+=','
    fi
  done
  INVOKE_CMD+='],"Function":"'
  INVOKE_CMD+=$FUNCTION_NAME
  INVOKE_CMD+='"}'
  # fire invoke/query
  local CMD="peer chaincode $MODE --orderer $ORDERER_HOST:$ORDERER_PORT --tls --cafile $ORDERER_CA -C $CHANNEL_NAME --name $CC_NAME -c '$INVOKE_CMD'"
  if [ -n "$ENDORSERS_ADDRESSES" ]; then
    CMD+="$ENDORSERS_ADDRESSES"
    CMD+="$ENDORSERS_CA_CERTS"
  fi
  [ $LOG_LEVEL -ge 3 ] && echo "$CMD"
  eval "$CMD"
  if [ $? != 0 ]; then
   echo "chaincode $MODE failed for function '$FUNCTION_NAME' with args '${ARGS_ARRAY[*]}'"
   exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
}