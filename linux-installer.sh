#/bin/bash
TAG_VERSION="v0.3.3"
VERSION="v0.3.3"
WORKING_DIR="beep-miner"
MINER_DIR="beepminer-${VERSION}"

print_logo() {
  echo "Welcome to Nimiqpocket.com"
}

# Check if we have root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    return 1
  fi
  return 0
}

# Check if we have yum package manager
#
# Adding a package:
# $ yum install curl -y
has_yum() {
  if [[ -n "$(command -v yum)" ]]; then
    return 0
  fi
  return 1
}

# Check if we have apt-get package manager
#
# Adding a package:
# $ apt-get install curl -y
has_apt() {
  if [[ -n "$(command -v apt-get)" ]]; then
    return 0
  fi
  return 1
}

# Check if we have apk package manager
#
# Adding a package:
# $ apk add curl
has_apk() {
  if [[ -n "$(command -v apk)" ]]; then
    return 0
  fi
  return 1
}

# Check if we have cURL
has_curl() {
  if [[ -n "$(command -v curl)" ]]; then
    return 0
  fi
  return 1
}

# Check if we have wget
has_wget() {
  if [[ -n "$(command -v wget)" ]]; then
    return 0
  fi
  return 1
}

has_unzip() {
  if [[ -n "$(command -v unzip)" ]]; then
    return 0
  fi
  return 1
}

has_screen() {
  if [[ -n "$(command -v screen)" ]]; then
    return 0
  fi
  return 1
}

# Returns true if we are on macOS
is_darwin() {
  unamestr=`uname`
  if [ "$unamestr" == "Darwin" ]; then
    return 0
  fi
  return 1
}

# Returns true if we are on Windows Subsystem for Linux
is_wsl() {
  wincheck=`uname -r | sed -n 's/.*\( *Microsoft *\).*/\1/p'`
  if [ "$wincheck" == "Microsoft" ]; then
    return 0
  fi
  return 1
}

update_pkgmgr() {
  if has_yum; then
    yum upgrade -y
  elif has_apt; then
    apt-get update -y
  fi
}

# install_pkg [yum_pkg] [apt_pkg] [apk_pkg]
install_pkg() {
  if has_yum; then
    yum install $1 -y
  elif has_apt; then
    apt-get install $2 -y
  elif has_apk; then
    apk --no-cache add $3 -y
  fi
}

install_curl() {
  if ! check_root; then
    echo "Cannot install cURL without root privileges!"
    exit 1
  fi
  install_pkg "curl" "curl" "curl"
}

install_unzip() {
  if ! check_root; then
    echo "Cannot install unzip without root privileges!"
    exit 1
  fi
  install_pkg "zip" "zip" "zip"
}

install_screen() {
  if ! check_root; then
    echo "Cannot install screen without root privileges!"
    exit 1
  fi
  install_pkg "screen" "screen" "screen"
}

# Download <url> <output_path>
download() {
  URL=$1
  OUTPUT_PATH=$2

  if has_curl; then
    curl -k -L "${URL}" -o $OUTPUT_PATH
  elif has_wget; then
    wget "${URL}" -O $OUTPUT_PATH
  fi

  unset URL
  unset OUTPUT_PATH
}

write_script() {
  echo "#!/bin/sh" > $1
  chmod +x $1
}

write_start_foreground_script() {
  write_script "start-foreground.sh"
  if [[ -n "$CPU_CORES" ]]; then
    echo "export UV_THREADPOOL_SIZE=${CPU_CORES}" >> "start-foreground.sh"
  fi
  echo $1 >> "start-foreground.sh"
}

write_start_background_script() {
  write_script "start-background.sh"
  if [[ -n "$CPU_CORES" ]]; then
    echo "export UV_THREADPOOL_SIZE=${CPU_CORES}" >> "start-background.sh"
  fi
  echo "screen -d -m -S miner ${1}" >> "start-background.sh"

  echo "echo \"Beep Miner has been started in the background.\"" >> "start-background.sh"
  echo "echo \"To attach to the background terminal, use the following command:\"" >> "start-background.sh"
  echo "echo \"\"" >> "start-background.sh"
  echo "echo \"screen -r miner\"" >> "start-background.sh"
  echo "echo \"\"" >> "start-background.sh"
  echo "echo \"Once attached, to detach, use the Ctrl+A, D shortcut.\"" >> "start-background.sh"
}

# Script starts here!
# Check for a download manager
if ! has_curl && ! has_wget; then
  install_curl
fi

if check_root; then
  # Update package manager in case we use it
  update_pkgmgr
fi

# Check for unzip
if ! has_unzip; then
  install_unzip
fi

# Check for screen
if ! has_screen; then
  install_screen
fi

print_logo

MINER_ZIP_FN="beepminer-${VERSION}.zip"
MINER_URL="https://miner.beeppool.org/downloads/${MINER_ZIP_FN}"

if [[ -z "$WALLET_ADDRESS" ]]; then
  echo "WALLET_ADDRESS was not defined!"
  exit 1
fi
PRETTY_WORKER_NAME=$WORKER_ID
if [[ -z ${WORKER_ID+x} ]]; then
  echo "WORKER_ID was not defined, using auto config ..."
  PRETTY_WORKER_NAME="<auto>"
  unset WORKER_ID
fi

echo "Installing Beep Miner with the following settings:"
echo "Wallet: ${WALLET_ADDRESS}"
echo "Worker Name: ${PRETTY_WORKER_NAME}"

# If we are in WSL, do a bit more
if is_wsl; then
  echo "TODO: Ask for root to setup screen" > /dev/null
  # TODO: Ask for root to setup screen
fi

# Make working directory
rm -rf $WORKING_DIR
mkdir -p $WORKING_DIR
cd $WORKING_DIR
download "${MINER_URL}" $MINER_ZIP_FN
unzip $MINER_ZIP_FN

# Install persistence
if [[ -n "$INSTALL_SERVICE" ]]; then
  echo "TODO: Service installation" > /dev/null
  # TODO
  # https://github.com/moby/moby/tree/master/contrib/init
  # systemd
  # sysvinit-debian
  # sysvinit-redhat
  # upstart
  # After installing the service, start it
else
  # Requested to install without service management
  # Clean-up the zip
  rm -f $MINER_ZIP_FN

  # Generate CPU cores flag
  CPU_CORES_LINE=""
  if [[ -n "$THREAD" ]]; then
    CPU_CORES_LINE=" --miner=${THREAD}"
  fi
  
  # Generate nonces per run flag
  SERVER_URL_DATA=""
  if [[ -n "$SERVER_URL" ]]; then
    SERVER_URL_DATA=" --pool=${SERVER_URL}"
  fi

  # Generate extra data flag
  EXTRADATA=""
  if [[ -n "$WORKER_ID" ]]; then
    EXTRADATA=" --deviceLabel=\"${WORKER_ID}\""
  fi

  # Write two files; start-foreground.sh / start-background.sh
  EXEC_LINE="./${MINER_DIR}/miner --wallet-address=\"${WALLET_ADDRESS}\"${CPU_CORES_LINE}${SERVER_URL_DATA}${EXTRADATA}"
  write_start_foreground_script "${EXEC_LINE}"
  write_start_background_script "${EXEC_LINE}"

  echo ""
  echo "The miner executable has been installed in the ${WORKING_DIR} directory."
  echo ""
  echo "To start the miner in the foreground, use the following command:"
  echo ""
  echo "cd ./${WORKING_DIR}/ && sh start-foreground.sh"
  echo ""
  echo "To start the miner in the background, use the following command:"
  echo ""
  echo "cd ./${WORKING_DIR}/ && sh start-background.sh"
  echo ""
  echo "--------------- Welcome to Nimiqpocket.com! Happy mining! ---------------"
  echo ""
fi

# Start background script
if [[ -n "$START_BACKGROUND" ]]; then
  echo "Automatically starting miner in background ..."
  ./start-background.sh
else  
  echo "Automatically starting miner in foreground ..."
  ./start-foreground.sh
fi
