function getAll() {
    if ! command -v git &> /dev/null
    then
        echo
        echo "Installing git"
        sudo apt-get install git
        echo
        echo "----------------- Download git finished --------------------------"
        echo
    fi
    if ! command -v curl &> /dev/null
    then
        echo
        echo "Installing curl"
        sudo apt-get install curl
        echo
        echo "----------------- Download curl finished --------------------------"
        echo
    fi
    if ! command -v jq &> /dev/null
    then
        echo
        echo "Installing jq"
        sudo apt-get install jq
        echo
        echo "----------------- Download jq finished --------------------------"
        echo
    fi
}

function installPrerequisites {
    echo
    echo "The script will now install all prerequisites for the network to run"
    echo
    echo "Do you want to install git? WARNING: this will make use of sudo apt-get"
    read -p "Enter y or n to confirm your choice, or enter Y to allow all prerequisites to be installed " -n 1 -r
    echo
    if [ "$REPLY" = "Y" ]; then
        getAll
    else
        if [ "$REPLY" = "y" ]; then
            if ! command -v git &> /dev/null
            then
                echo
                echo "Installing git"
                sudo apt-get install git
                echo
                echo "----------------- Download git finished --------------------------"
                echo
            fi
            if ! command -v curl &> /dev/null
            then
                echo
                echo "Installing curl"
                sudo apt-get install curl
                echo
                echo "----------------- Download curl finished --------------------------"
                echo
            fi
            if ! command -v jq &> /dev/null
            then
                echo
                echo "Installing jq"
                sudo apt-get install jq
                echo
                echo "----------------- Download jq finished --------------------------"
                echo
            fi
        fi
    fi
}

function downloadBinaries {
    PWD_OLD=$PWD
    DIR_="$(dirname "$(dirname "$(realpath "$BASH_SOURCE")")")"
    FILE="$DIR_/bin/configtxgen"
    BIN="$DIR_/bin"
    cd "$DIR_"
    if [ ! -f "$FILE" ]; then
        if [ ! -d "$BIN" ]; then
            mkdir bin
        else
            rm -Rf bin
            mkdir bin
        fi
        cd "$BIN"
        echo
        echo "----------------- Downloading binaries - please wait... --------------------------"
        echo
        git clone -b 2.2.0_lin https://github.com/AstraKode-Blockchain/hyperledger-fabric-binaries.git
        cp -a hyperledger-fabric-binaries/. "$BIN"
        rm -Rf hyperledger-fabric-binaries
        rm -Rf .git
        echo
        echo "----------------- Download binaries finished --------------------------"
        echo
    fi
    cd "$PWD_OLD"
}

function binariesMain {
    installPrerequisites
    downloadBinaries
}