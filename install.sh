#!/bin/bash
# install.sh: Usernetes install script. This version of install.sh is modified
# to set up usernetes in pb-system-tools' "Unprivileged Kubernetes" (u21s) mode.
# Some of the command line configs are irreleveant/obsolete/non-functional in
# this version, e.g. the networking related ones, since u21s takes care of
# networking outside of u7s.
# This modification adds new config options via the environment. The following
# variables can be configured.
#
# export U7S_CLUSTER_DOMAIN=cluster.local
# export U7S_SERVICE_CLUSTER_IP_RANGE=10.0.0.0/16
# export U7S_DNS_CLUSTER_IP=10.0.0.53
# export U7S_CNI_BRIDGE_SUBNET=10.88.0.0/16
# # Optional:
# export U7S_DNS_EXTERNAL_IP=
# # Then run this script as usual:
# ./install.sh

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

### Set config vars
set +u
if [ -z "$HOME" ]; then
	ERROR "HOME needs to be set"
	exit 1
fi
config_dir="$HOME/.config"
if [ -n "$XDG_CONFIG_HOME" ]; then
	config_dir="$XDG_CONFIG_HOME"
fi

if [ "$U7S_DNS_EXTERNAL_IP" ]; then
  U7S_DNS_EXTERNAL_IP_STANZA="  externalIPs:
    - $U7S_DNS_EXTERNAL_IP"
else
  U7S_DNS_EXTERNAL_IP_STANZA=
fi
set -u

### Load u21s config for NETNS_ADDR config var, and set default config vars
source "/etc/pb-system-tools/u21s@$(id -un).conf" || {
  echo "Failed to source /etc/pb-system-tools/u21s@$(id -un).conf"
  exit 1
}

: ${U7S_CLUSTER_DOMAIN:-cluster.local}
: ${U7S_SERVICE_CLUSTER_IP_RANGE:-10.0.0.0/16}
: ${U7S_DNS_CLUSTER_IP:-10.0.0.53}
: ${U7S_DNS_REPLICAS:-2}
: ${U7S_CNI_BRIDGE_SUBNET:-10.88.0.0/16}
# Export for cfssl.sh:
export U7S_CLUSTER_DOMAIN

### Parse args
arg0=$0
start="u7s.target"
cri="containerd"
cni=""
publish=""
publish_default="0.0.0.0:6443:6443/tcp"
cidr="10.0.42.0/24"
delay=""
wait_init_certs=""
function usage() {
	echo "Usage: ${arg0} [OPTION]..."
	echo "Install Usernetes systemd units to ${config_dir}/systemd/unit ."
	echo
	echo "  --start=UNIT        Enable and start the specified target after the installation, e.g. \"u7s.target\". Set to an empty to disable autostart. (Default: \"$start\")"
	echo "  --cri=RUNTIME       Specify CRI runtime, \"containerd\" or \"crio\". (Default: \"$cri\")"
	echo '  --cni=RUNTIME       Specify CNI, an empty string (none) or "flannel". (Default: none)'
	echo "  -p, --publish=PORT  Publish ports in RootlessKit's network namespace, e.g. \"0.0.0.0:10250:10250/tcp\". Can be specified multiple times. (Default: \"${publish_default}\")"
	echo "  --cidr=CIDR         Specify CIDR of RootlessKit's network namespace, e.g. \"10.0.100.0/24\". (Default: \"$cidr\")"
	echo
	echo "Examples:"
	echo "  # The default options"
	echo "  ${arg0}"
	echo
	echo "  # Use CRI-O as the CRI runtime"
	echo "  ${arg0} --cri=crio"
	echo
	echo 'Use `uninstall.sh` for uninstallation.'
	echo 'For an example of multi-node cluster with flannel, see docker-compose.yaml'
	echo
	echo 'Hint: `sudo loginctl enable-linger` to start user services automatically on the system start up.'
}

set +e
args=$(getopt -o hp: --long help,publish:,start:,cri:,cni:,cidr:,,delay:,wait-init-certs -n $arg0 -- "$@")
getopt_status=$?
set -e
if [ $getopt_status != 0 ]; then
	usage
	exit $getopt_status
fi
eval set -- "$args"
while true; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		shift
		;;
	-p | --publish)
		publish="$publish $2"
		shift 2
		;;
	--start)
		start="$2"
		shift 2
		;;
	--cri)
		cri="$2"
		case "$cri" in
		"" | containerd | crio) ;;

		*)
			ERROR "Unknown CRI runtime \"$cri\". Supported values: \"containerd\" (default) \"crio\" \"\"."
			exit 1
			;;
		esac
		shift 2
		;;
	--cni)
		cni="$2"
		case "$cni" in
		"" | "flannel") ;;

		*)
			ERROR "Unknown CNI \"$cni\". Supported values: \"\" (default) \"flannel\" ."
			exit 1
			;;
		esac
		shift 2
		;;
	--cidr)
		cidr="$2"
		shift 2
		;;
	--delay)
		# HIDDEN FLAG. DO NO SPECIFY MANUALLY.
		delay="$2"
		shift 2
		;;
	--wait-init-certs)
		# HIDDEN FLAG FOR DOCKER COMPOSE. DO NO SPECIFY MANUALLY.
		wait_init_certs=1
		shift 1
		;;
	--)
		shift
		break
		;;
	*)
		break
		;;
	esac
done

# set default --publish if none was specified
if [[ -z "$publish" ]]; then
	publish=$publish_default
fi

# check cgroup config
if [[ ! -f /sys/fs/cgroup/cgroup.controllers ]]; then
	ERROR "Needs cgroup v2, see https://rootlesscontaine.rs/getting-started/common/cgroup2/"
	exit 1
else
	f="/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers"
	if [[ ! -f $f ]]; then
		ERROR "systemd not running? file not found: $f"
		exit 1
	fi
	if ! grep -q cpu $f; then
		WARNING "cpu controller might not be enabled, you need to configure /etc/systemd/system/user@.service.d , see https://rootlesscontaine.rs/getting-started/common/cgroup2/"
	elif ! grep -q memory $f; then
		WARNING "memory controller might not be enabled, you need to configure /etc/systemd/system/user@.service.d , see https://rootlesscontaine.rs/getting-started/common/cgroup2/"
	else
		INFO "Rootless cgroup (v2) is supported"
	fi
fi

# Delay for debugging
if [[ -n "$delay" ]]; then
	INFO "Delay: $delay seconds..."
	sleep "$delay"
fi

### Create EnvironmentFile (~/.config/usernetes/env)

mkdir -p ${config_dir}/usernetes
cat /dev/null >${config_dir}/usernetes/env
cat <<EOF >>${config_dir}/usernetes/env
U7S_KUBE_APISERVER_BIND_ADDRESS=${NETNS_ADDR%/*}
U7S_CLUSTER_DOMAIN=${U7S_CLUSTER_DOMAIN}
U7S_SERVICE_CLUSTER_IP_RANGE=${U7S_SERVICE_CLUSTER_IP_RANGE}
U7S_DNS_CLUSTER_IP=${U7S_DNS_CLUSTER_IP}
EOF
if [ "$cni" = "flannel" ]; then
	cat <<EOF >>${config_dir}/usernetes/env
U7S_FLANNEL=1
EOF
fi

### Render config templates
# CoreDNS
render_template U7S_CLUSTER_DOMAIN \
                U7S_DNS_CLUSTER_IP \
                U7S_DNS_EXTERNAL_IP_STANZA \
                U7S_DNS_REPLICAS \
                < manifests/coredns.yaml.template \
                > manifests/coredns.yaml

# CNI bridge
render_template U7S_CNI_BRIDGE_SUBNET \
                < config/node1/cni_net.d/50-bridge.conf.template \
                > config/node1/cni_net.d/50-bridge.conf


### Setup SSL certs
master=${NETNS_ADDR%/*}
if [[ -n "$wait_init_certs" ]]; then
	max_trial=300
	INFO "Waiting for certs to be created.":
	for ((i = 0; i < max_trial; i++)); do
		if [[ -f ${config_dir}/usernetes/node/done || -f ${config_dir}/usernetes/master/done ]]; then
			echo "OK"
			break
		fi
		echo -n .
		sleep 5
	done
elif [[ ! -d ${config_dir}/usernetes/master ]]; then
	### If the keys are not generated yet, generate them for the single-node cluster
	INFO "Generating single-node cluster TLS keys (${config_dir}/usernetes/{master,node})"
	cfssldir=$(mktemp -d /tmp/cfssl.XXXXXXXXX)
	node=$(hostname)
	${base}/common/cfssl.sh --dir=${cfssldir} --master=$master --node="${node},127.0.0.1"
	rm -rf ${config_dir}/usernetes/{master,node}
	cp -r "${cfssldir}/master" ${config_dir}/usernetes/master
	cp -r "${cfssldir}/nodes.$node" ${config_dir}/usernetes/node
	rm -rf "${cfssldir}"
fi

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

### u7s
cat <<EOF | x u7s.target
[Unit]
Description=Usernetes target (all components in the single node)
Requires=u7s-master-with-etcd.target u7s-node.target
After=u7s-master-with-etcd.target u7s-node.target

[Install]
WantedBy=default.target
EOF

cat <<EOF | x u7s-master-with-etcd.target
[Unit]
Description=Usernetes target for Kubernetes master components (including etcd)
Requires=u7s-etcd.target u7s-master.target
After=u7s-etcd.target u7s-master.target
PartOf=u7s.target

[Install]
WantedBy=u7s.target
EOF

### RootlessKit
if [ -n "$cri" ]; then
	cat <<EOF | x u7s-rootlesskit.service
[Unit]
Description=Usernetes RootlessKit service ($cri)
PartOf=u7s.target

[Service]
ExecStart=${base}/boot/rootlesskit.sh ${base}/boot/${cri}.sh
Delegate=yes
${service_common}
EOF
else
	cat <<EOF | x u7s-rootlesskit.service
[Unit]
Description=Usernetes RootlessKit service
PartOf=u7s.target

[Service]
ExecStart=${base}/boot/rootlesskit.sh
Delegate=yes
${service_common}
EOF
fi

### etcd
# TODO: support running without RootlessKit
cat <<EOF | x u7s-etcd.target
[Unit]
Description=Usernetes target for etcd
Requires=u7s-etcd.service
After=u7s-etcd.service
PartOf=u7s-master-with-etcd.target
EOF

cat <<EOF | x u7s-etcd.service
[Unit]
Description=Usernetes etcd service
BindsTo=u7s-rootlesskit.service
PartOf=u7s-etcd.target

[Service]
Type=notify
NotifyAccess=all
# Bash exits with status 129 on SIGHUP (128 + signum:1)
SuccessExitStatus=129
ExecStart=${base}/boot/etcd.sh
ExecStartPost=${base}/boot/etcd-init-data.sh
${service_common}
EOF

### master
# TODO: support running without RootlessKit
# TODO: decouple from etcd (for supporting etcd on another node)
cat <<EOF | x u7s-master.target
[Unit]
Description=Usernetes target for Kubernetes master components
Requires=u7s-kube-apiserver.service u7s-kube-controller-manager.service u7s-kube-scheduler.service
After=u7s-kube-apiserver.service u7s-kube-controller-manager.service u7s-kube-scheduler.service
PartOf=u7s-master-with-etcd.target

[Install]
WantedBy=u7s-master-with-etcd.target
EOF

cat <<EOF | x u7s-kube-apiserver.service
[Unit]
Description=Usernetes kube-apiserver service
BindsTo=u7s-rootlesskit.service
Requires=u7s-etcd.service
After=u7s-etcd.service
PartOf=u7s-master.target

[Service]
Type=notify
NotifyAccess=all
ExecStart=${base}/boot/kube-apiserver.sh
${service_common}
EOF

cat <<EOF | x u7s-kube-controller-manager.service
[Unit]
Description=Usernetes kube-controller-manager service
BindsTo=u7s-rootlesskit.service
Requires=u7s-kube-apiserver.service
After=u7s-kube-apiserver.service
PartOf=u7s-master.target

[Service]
ExecStart=${base}/boot/kube-controller-manager.sh
${service_common}
EOF

cat <<EOF | x u7s-kube-scheduler.service
[Unit]
Description=Usernetes kube-scheduler service
BindsTo=u7s-rootlesskit.service
Requires=u7s-kube-apiserver.service
After=u7s-kube-apiserver.service
PartOf=u7s-master.target

[Service]
ExecStart=${base}/boot/kube-scheduler.sh
${service_common}
EOF

### node
if [ -n "$cri" ]; then
	cat <<EOF | x u7s-node.target
[Unit]
Description=Usernetes target for Kubernetes node components (${cri})
Requires=u7s-kubelet-${cri}.service u7s-kube-proxy.service $([ "$cni" = "flannel" ] && echo u7s-flanneld.service)
After=u7s-kubelet-${cri}.service u7s-kube-proxy.service $([ "$cni" = "flannel" ] && echo u7s-flanneld.service)
PartOf=u7s.target

[Install]
WantedBy=u7s.target
EOF

	cat <<EOF | x u7s-kubelet-${cri}.service
[Unit]
Description=Usernetes kubelet service (${cri})
BindsTo=u7s-rootlesskit.service
PartOf=u7s-node.target

[Service]
Type=notify
NotifyAccess=all
ExecStart=${base}/boot/kubelet-${cri}.sh
${service_common}
EOF

	cat <<EOF | x u7s-kube-proxy.service
[Unit]
Description=Usernetes kube-proxy service
BindsTo=u7s-rootlesskit.service
Requires=u7s-kubelet-${cri}.service
After=u7s-kubelet-${cri}.service
PartOf=u7s-node.target

[Service]
ExecStart=${base}/boot/kube-proxy.sh
${service_common}
EOF

	if [ "$cni" = "flannel" ]; then
		cat <<EOF | x u7s-flanneld.service
[Unit]
Description=Usernetes flanneld service
BindsTo=u7s-rootlesskit.service
PartOf=u7s-node.target

[Service]
ExecStart=${base}/boot/flanneld.sh
${service_common}
EOF
	fi
fi


### Finish installation
systemctl --user daemon-reload
INFO "Installation complete."
INFO "Start unprivileged kubernetes with \`sudo systemctl start u21s@\$(id -u).target\`."
INFO "Then, run \`kubectl apply -f ${base}/manifests/coredns.yaml\` to install CoreDNS."
INFO 'Hint: `sudo loginctl enable-linger` to start user services automatically on the system start up.'
if [[ -n "${KUBECONFIG}" ]]; then
  INFO "Hint: export KUBECONFIG=$HOME/.config/usernetes/master/admin-${master}.kubeconfig"
fi
