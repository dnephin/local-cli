#!/usr/bin/env bash

set -eu

PICARD_REPO="circleci/picard"

PICARD_CLI_URL="https://circle-downloads.s3.amazonaws.com/releases/build_agent_wrapper/circleci"
PICARD_CLI_FILE="$0"

CIRCLECI_DIR="$HOME/.circleci"
CURRENT_DIGEST_FILE="$CIRCLECI_DIR/current_picard_digest"
LATEST_DIGEST_FILE="$CIRCLECI_DIR/latest_picard_digest"

UNKNOWN_DIGEST=""

CLI_VERSION="0.0.4705-deba4df"

# Pull `latest` tag from docker repo and write digest into the file
pull_latest_image() {
  local latest_image=$(docker pull $PICARD_REPO | grep -o "sha256.*$")
  echo $latest_image > $LATEST_DIGEST_FILE
}

# Write given digest into the file
update_current_digest() {
  local version="$@"
  echo $version > $CURRENT_DIGEST_FILE
}

# Read latest digest from file
get_latest_digest() {
  if [ -e "$LATEST_DIGEST_FILE" ];
  then
    echo "$(cat "$LATEST_DIGEST_FILE")"
  else
    echo "$UNKNOWN_DIGEST"
  fi
}

# Read current digest from file
get_current_digest() {
  if [ -e "$CURRENT_DIGEST_FILE" ];
  then
    echo "$(cat "$CURRENT_DIGEST_FILE")"
  else
    echo $UNKNOWN_DIGEST
  fi
}

# Compare latest_digest and current_digest
is_update_available() {
  current=$(get_current_digest)
  latest=$(get_latest_digest)

  return $([[ $latest != $UNKNOWN_DIGEST ]] && [[ $current != $latest ]])
}

# Printing version of this script
print_cli_version() {
  echo "Local CLI version: $CLI_VERSION"
}

#
# Main program
#
if [ ! -e "$CIRCLECI_DIR" ];
then
  mkdir -p "$CIRCLECI_DIR" >/dev/null
fi

case "${1-}" in
  # Option for development purpose only
  --image | -i )
    picard_image="$2"
    shift; shift;
    echo "[WARN] Using circleci: $picard_image"
    ;;

  --tag | -t )
    picard_image="$PICARD_REPO:$2"
    shift; shift;
    echo "[WARN] Using circleci: $picard_image"
	;;

  --version )
    echo $CLI_VERSION
    exit 0
esac

# Do not check for update if --image of --tag is specified (to avoid overriding :latest tag)
if [[ ! ${picard_image-} ]]; then
  current_digest=$(get_current_digest)
  if [[ $current_digest == $UNKNOWN_DIGEST ]]; then
    # Receiving latest image of picard in case of there's no current digest stored
    echo "Downloading latest CircleCI build agent..."
    pull_latest_image >/dev/null
    current_digest=$(get_latest_digest)
    update_current_digest $current_digest
  else
    # Otherwise pulling latest image in background
    pull_latest_image &>/dev/null &disown
  fi
  picard_image="$PICARD_REPO@$current_digest"
fi

case "${1-}" in
  version )
    print_cli_version
    ;;

  update )
    echo "Updating CircleCI build agent..."
    current_digest=$(get_latest_digest)
    update_current_digest $current_digest
    echo "Done"
    exit 0
    ;;

  "" )
    set -- "-h"
esac

if is_update_available; then
  echo "INFO: There's a newer version of the CircleCI build agent available. Run 'circleci update' to update."
fi

pwd="$(pwd)"
exec docker run -it --rm \
       -e "DOCKER_API_VERSION=${DOCKER_API_VERSION:-1.23}" \
       -v /var/run/docker.sock:/var/run/docker.sock \
       -v "$pwd:$pwd" \
       -v ~/.circleci/:/root/.circleci \
       --workdir "$pwd" \
       "$picard_image" \
       circleci "${@-}"
