#!/bin/bash
export U7S_BASE_DIR=$(realpath $(dirname $0)/..)
source $U7S_BASE_DIR/common/common.inc.sh

mkdir -p $XDG_RUNTIME_DIR/usernetes

export RK_INSTANCE=2
exec $(dirname $0)/nsenter.sh kube-proxy \
	--config $XDG_RUNTIME_DIR/usernetes/kube-proxy-config.yaml \
	$@
