#!/bin/bash

# install_scripts.sh INSTALL_DIR
# Run this to overwrite scripts of a u7s installation at INSTALL_DIR with
# scripts from another source tree (e.g. a local copy of the u7s git repo). This
# is useful when you downloaded and unpacked u7s binaries from a tarball release
# (See https://github.com/rootless-containers/usernetes/releases) but want to
# use the install/wrapper scripts from source.

[ -z "$BASH_SOURCE" ] &&
  { echo "BASH_SOURCE is unset, exiting."; exit 1; } ||
    cd "$(dirname "$(realpath "$BASH_SOURCE")")"

set -e

INSTALL_DIR="$1"
[ -d "$INSTALL_DIR" ] || {
  echo "usage: $0 INSTALL_DIR"
  echo "INSTALL_DIR '$INSTALL_DIR' does not exists or is not a directory."
  exit 1
}

cp boot/* "$INSTALL_DIR/boot"
cp common/* "$INSTALL_DIR/common"
cp -r config/ "$INSTALL_DIR/"
cp manifests/* "$INSTALL_DIR/manifests"
cp install.sh install_node2.sh uninstall.sh wipe.sh "$INSTALL_DIR"
