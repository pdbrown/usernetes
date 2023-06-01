#!/bin/bash
export U7S_BASE_DIR=$(realpath $(dirname $0)/..)
source $U7S_BASE_DIR/common/common.inc.sh

export RK_INSTANCE=2
exec $(dirname $0)/nsenter.sh kubelet \
	--cert-dir $XDG_CONFIG_HOME/usernetes/pki \
	--root-dir $XDG_DATA_HOME/usernetes/kubelet-node2 \
	--kubeconfig $XDG_CONFIG_HOME/usernetes/node/node.kubeconfig \
	--config $XDG_RUNTIME_DIR/usernetes/kubelet-config.yaml \
        --container-runtime-endpoint unix://$XDG_RUNTIME_DIR/usernetes/containerd2/containerd.sock \
	$@
