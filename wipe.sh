#!/bin/bash
set -e -o pipefail
cd $(dirname $0)
if [ -z $HOME ]; then
  echo "HOME needs to be set"
  exit 1
fi
config_dir="$HOME/.config"
if [ -n "$XDG_CONFIG_HOME" ]; then
  config_dir="$XDG_CONFIG_HOME"
fi
data_dir="$HOME/.local/share"
set -u
set +e
set -x

# Restore permissions to containerd snapshot dirs
find "$data_dir/usernetes" -type d -perm 000 2> /dev/null | xargs --no-run-if-empty chmod u+rwx
# And delete
rm -rf "$config_dir/usernetes" "$data_dir/usernetes"
