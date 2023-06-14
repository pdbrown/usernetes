#!/bin/bash
export U7S_BASE_DIR=$(realpath $(dirname $0)/..)
source $U7S_BASE_DIR/common/common.inc.sh

mkdir -p $XDG_RUNTIME_DIR/usernetes
cat >$XDG_RUNTIME_DIR/usernetes/kubelet-config.yaml <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
volumePluginDir: $XDG_DATA_HOME/usernetes/kubelet-plugins-exec
authentication:
  anonymous:
    enabled: false
  x509:
    clientCAFile: "$XDG_CONFIG_HOME/usernetes/node/ca.pem"
tlsCertFile: "$XDG_CONFIG_HOME/usernetes/node/node.pem"
tlsPrivateKeyFile: "$XDG_CONFIG_HOME/usernetes/node/node-key.pem"
clusterDomain: "$U7S_CLUSTER_DOMAIN"
clusterDNS:
  - "$U7S_DNS_CLUSTER_IP"
failSwapOn: false
featureGates:
  KubeletInUserNamespace: true
evictionHard:
  nodefs.available: "3%"
localStorageCapacityIsolation: false
cgroupDriver: "cgroupfs"
cgroupsPerQOS: true
enforceNodeAllocatable: []
EOF

# exec $(dirname $0)/nsenter.sh kubelet \
# 	--cert-dir $XDG_CONFIG_HOME/usernetes/pki \
# 	--root-dir $XDG_DATA_HOME/usernetes/kubelet \
# 	--kubeconfig $XDG_CONFIG_HOME/usernetes/node/node.kubeconfig \
# 	--config $XDG_RUNTIME_DIR/usernetes/kubelet-config.yaml \
# 	$@

SUPPRESS_ERRORS=(
  # These are related to the filesystem stats problem, maybe due to
  # device mapper disk name vs uuid mismatch, see notes/unix.org

  # Feb 02 10:37:19 mars kubelet-containerd.sh[303310]: E0202 10:37:19.292975      90 cri_stats_provider.go:455] "Failed to get the info of the filesystem with mountpoint" err="cannot find filesystem info for device \"/dev/mapper/mirror0_crypt\"" mountpoint="/home/phil/.local/share/usernetes/containerd/io.containerd.snapshotter.v1.overlayfs"
  "cannot find filesystem info for device"

  # Feb 02 13:39:08 mars kubelet-containerd.sh[304154]: E0202 13:39:08.127980      90 kubelet.go:1335] "Image garbage collection failed multiple times in a row" err="invalid capacity 0 on image filesystem"
  "Image garbage collection failed"

  # Not sure why oom_score_adj is failing
  # Feb 02 13:34:15 mars kubelet-containerd.sh[304154]: E0202 13:34:15.489937      90 container_manager_linux.go:545] "Failed to ensure process in container with oom score" err="failed to apply oom score -999 to PID 90: write /proc/90/oom_score_adj: permission denied"
  "Failed to ensure process in container with oom score"
)

$(dirname $0)/nsenter.sh kubelet \
	--cert-dir $XDG_CONFIG_HOME/usernetes/pki \
	--root-dir $XDG_DATA_HOME/usernetes/kubelet \
	--kubeconfig $XDG_CONFIG_HOME/usernetes/node/node.kubeconfig \
	--config $XDG_RUNTIME_DIR/usernetes/kubelet-config.yaml \
	$@ 2>&1 |
  grep --line-buffered -v "$(printf "%s\n" "${SUPPRESS_ERRORS[@]}")"

# Notes
# evictrionHard: Relax disk pressure taint for CI
# LocalStorageCapacityIsolation=false: workaround for "Failed to start ContainerManager failed to get rootfs info" error on Fedora 32: https://github.com/rootless-containers/usernetes/pull/157#issuecomment-621008594

# 2022-02-02 pbrown: remove exec and add grep -v to filter out error spam
