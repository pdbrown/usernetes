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

rm -rf "$config_dir/usernetes" "$data_dir/usernetes"
