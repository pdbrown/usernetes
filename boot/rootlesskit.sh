#!/bin/bash
# Customizable environment variables:
# * $U7S_ROOTLESSKIT_FLAGS
# * $U7S_ROOTLESSKIT_PORTS
# * $U7S_FLANNEL

export U7S_BASE_DIR=$(realpath $(dirname $0)/..)
source $U7S_BASE_DIR/common/common.inc.sh

: ${RK_INSTANCE:=1}
rk_state_dir=$XDG_RUNTIME_DIR/usernetes/rootlesskit-$RK_INSTANCE
mkdir -p "$rk_state_dir"

: ${U7S_ROOTLESSKIT_FLAGS=}
: ${U7S_ROOTLESSKIT_PORTS=}
: ${U7S_FLANNEL=}

: ${_U7S_CHILD=0}
if [[ $_U7S_CHILD == 0 ]]; then
	_U7S_CHILD=1
	if hostname -I &>/dev/null ; then
		: ${U7S_PARENT_IP=$(hostname -I | sed -e 's/ .*//g')}
	else
		: ${U7S_PARENT_IP=$(hostname -i | sed -e 's/ .*//g')}
	fi
	export _U7S_CHILD U7S_PARENT_IP

	pb-rootlesskit --pidfile "$rk_state_dir/child_pid" \
		--hook "pb-rootlesskit copy_up /etc /run /opt /var/lib" \
		--hook "hostname $(hostname -s)-u7sn${RK_INSTANCE}" \
		--hook "u21s-dnsmasq '$HOME/.config/usernetes/u21s-dnsmasq.conf'" \
		"$0" "$@"

else
	# save IP address
	echo $U7S_PARENT_IP >$XDG_RUNTIME_DIR/usernetes/parent_ip

	# Remove symlinks so that the child won't be confused by the parent configuration
	rm -f \
		/run/xtables.lock /run/flannel /run/netns \
		/run/runc /run/crun \
		/run/containerd /run/containers /run/crio \
		/etc/cni \
		/etc/containerd /etc/containers /etc/crio \
		/etc/kubernetes \
		/var/lib/kubelet /var/lib/cni /var/lib/containerd

	# Copy CNI config to /etc/cni/net.d (Likely to be hardcoded in CNI installers)
	mkdir -p /etc/cni/net.d
	cp -f $U7S_BASE_DIR/config/cni_net.d/* /etc/cni/net.d
	if [[ $U7S_FLANNEL == 1 ]]; then
		cp -f $U7S_BASE_DIR/config/flannel/cni_net.d/* /etc/cni/net.d
		mkdir -p /run/flannel
	fi

	# Hack to tweak bridge network for node2. Need to use a different
	# network so hostns can route between nodes(so between 10.88.0.0 and 10.89.0.0).
	set +u
	if [ "$RK_INSTANCE" = "2" ]; then
		sed -i 's/10.88.0.0/10.89.0.0/' /etc/cni/net.d/50-bridge.conf
	fi
	set -u

	# Bind-mount /opt/cni/net.d (Likely to be hardcoded in CNI installers)
	mkdir -p /opt/cni/bin
	mount --bind $U7S_BASE_DIR/bin/cni /opt/cni/bin

	# These bind-mounts are needed at the moment because the paths are
	# hard-coded in Kube and CRI-O.
	binds=(/var/lib/kubelet /var/lib/cni /var/log /var/lib/containers /var/cache)
	for f in ${binds[@]}; do
		src=$XDG_DATA_HOME/usernetes/node${RK_INSTANCE}_bind/$(echo $f | sed -e s@/@_@g)
		if [[ -L $f ]]; then
			# Remove link created by `rootlesskit --copy-up` if any
			rm -rf $f
		fi
		mkdir -p $src $f
		mount --bind $src $f
	done

	rk_pid=$(cat $rk_state_dir/child_pid)
	# workaround for https://github.com/rootless-containers/rootlesskit/issues/37
	# child_pid might be created before the child is ready
	echo $rk_pid >$rk_state_dir/_child_pid.u7s-ready
	log::info "RootlessKit ready, PID=${rk_pid}, state directory=$rk_state_dir ."
	log::info "Hint: You can enter RootlessKit namespaces by running \`nsenter -U --preserve-credential -n -m -t ${rk_pid}\`."
	if [[ -n $U7S_ROOTLESSKIT_PORTS ]]; then
		rootlessctl --socket $rk_state_dir/api.sock add-ports $U7S_ROOTLESSKIT_PORTS
	fi
	rc=0
	if [[ $# -eq 0 ]]; then
		sleep infinity || rc=$?
	else
		$@ || rc=$?
	fi
	log::info "RootlessKit exiting (status=$rc)"
	exit $rc
fi
