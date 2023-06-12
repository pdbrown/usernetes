#!/bin/bash
set -e -o pipefail

### Detect base dir
cd $(dirname $0)
base=$(realpath $(pwd))
source "$base/common/install.inc.sh"

### Detect bin dir, fail early if not found
if [ ! -d "$base/bin" ]; then
	ERROR "Usernetes binaries not found. Run \`make\` to build binaries. If you are looking for binary distribution of Usernetes, see https://github.com/rootless-containers/usernetes/releases ."
	exit 1
fi

### Detect config dir
set +u
if [ -z "$HOME" ]; then
	ERROR "HOME needs to be set"
	exit 1
fi
config_dir="$HOME/.config"
if [ -n "$XDG_CONFIG_HOME" ]; then
	config_dir="$XDG_CONFIG_HOME"
fi
set -u

### Render config templates
# CNI bridge
mkdir -p config/node2/cni_net.d
render_template U7S_CNI_BRIDGE_SUBNET \
                < config/node1/cni_net.d/50-bridge.conf.template \
                > config/node2/cni_net.d/50-bridge.conf


### Begin installation
INFO "Base dir: ${base}"
mkdir -p ${config_dir}/systemd/user
function x() {
	name=$1
	path=${config_dir}/systemd/user/${name}
	INFO "Installing $path"
	cat >$path
}

service_common="WorkingDirectory=${base}
EnvironmentFile=${config_dir}/usernetes/env
Restart=on-failure
LimitNOFILE=65536
"

cat <<EOF | x u7s-rootlesskit_node2.service
[Unit]
Description=Usernetes RootlessKit service containerd for node 2
PartOf=u7s-node2.target

[Service]
Environment=RK_INSTANCE=2
ExecStart=${base}/boot/rootlesskit.sh ${base}/boot/containerd_node2.sh
Delegate=yes
${service_common}
EOF

cat <<EOF | x u7s-kubelet_node2.service
[Unit]
Description=Usernetes kubelet service for node 2
Requires=u7s-rootlesskit_node2.service
After=u7s-rootlesskit_node2.service

[Service]
Type=notify
NotifyAccess=all
ExecStart=${base}/boot/kubelet_node2.sh
${service_common}
EOF

cat <<EOF | x u7s-kube-proxy_node2.service
[Unit]
Description=Usernetes kube-proxy service for node2
Requires=u7s-kubelet_node2.service
After=u7s-kubelet_node2.service

[Service]
ExecStart=${base}/boot/kube-proxy_node2.sh
${service_common}
EOF

cat <<EOF | x u7s-node2.target
[Unit]
Description=Usernetes target for Kubernetes node2 components
Requires=u7s-kube-proxy_node2.service
After=u7s-kube-proxy_node2.service
EOF


### Finish installation
systemctl --user daemon-reload
INFO "Installation complete."
INFO 'Start second kubernetes node with `systemctl --user start u7s-node2.target`'
