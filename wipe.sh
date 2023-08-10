#!/bin/bash
# wipe.sh USERNAME
set -e -o pipefail

if ! [ "$1" ]; then
  echo "Usage: $0 USERNAME"
  exit 1
fi

USER_HOME=$(bash -c "cd ~$(printf %q "$1") && pwd")

config_dir="$USER_HOME/.config"
data_dir="$USER_HOME/.local/share"

echo About to run
echo rm -rf \"$config_dir/usernetes\" \"$data_dir/usernetes\"

function read_char() {
  local prompt=$1
  read -r -p "$prompt" -n 1 reply
  echo ""
}

read_char "Continue? [yN] "
case "$reply" in
  y|Y)
    sudo rm -rf "$config_dir/usernetes" "$data_dir/usernetes"
    ;;
esac
