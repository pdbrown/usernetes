#!/bin/bash
export U7S_BASE_DIR=$(realpath $(dirname $0)/..)
source $U7S_BASE_DIR/common/common.inc.sh

exec $(dirname $0)/nsenter.sh kube-apiserver \
	--etcd-cafile=$XDG_CONFIG_HOME/usernetes/master/ca.pem \
	--etcd-certfile=$XDG_CONFIG_HOME/usernetes/master/kubernetes.pem \
	--etcd-keyfile=$XDG_CONFIG_HOME/usernetes/master/kubernetes-key.pem \
	--etcd-servers https://127.0.0.1:2379 \
	--client-ca-file=$XDG_CONFIG_HOME/usernetes/master/ca.pem \
	--kubelet-certificate-authority=$XDG_CONFIG_HOME/usernetes/master/ca.pem \
	--kubelet-client-certificate=$XDG_CONFIG_HOME/usernetes/master/kubernetes.pem \
	--kubelet-client-key=$XDG_CONFIG_HOME/usernetes/master/kubernetes-key.pem \
	--tls-cert-file=$XDG_CONFIG_HOME/usernetes/master/kubernetes.pem \
	--tls-private-key-file=$XDG_CONFIG_HOME/usernetes/master/kubernetes-key.pem \
	--service-account-key-file=$XDG_CONFIG_HOME/usernetes/master/service-account.pem \
	--service-cluster-ip-range=$U7S_SERVICE_CLUSTER_IP_RANGE \
	--service-account-issuer="https://kubernetes.default.svc.$U7S_CLUSTER_DOMAIN" \
	--service-account-signing-key-file=$XDG_CONFIG_HOME/usernetes/master/service-account-key.pem \
	--bind-address=0.0.0.0 \
	--allow-privileged \
	$@

# TODO: enable --authorization-mode=Node,RBAC \
