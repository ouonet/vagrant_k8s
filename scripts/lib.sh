#!/usr/bin/env bash
this_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
env_file="$this_dir/../.env"
env_default_file="$this_dir/../.env.default"
if [ -f $env_default_file ]; then
  source $env_default_file
fi
if [ -f "$env_file" ]; then
  source "$env_file"
fi

function logCurrentFunction() {
  echo "################################ ${FUNCNAME[1]} $1 ################################" 
}

# $1: interface, default eth1
function getIp() {
  K8S_INTERFACE=${K8S_INTERFACE:-"eth1"}
  ip_address=$(ip -4 addr show "$K8S_INTERFACE" | grep -v secondary | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  echo "$ip_address"
}

function setTimeZone() {
  echo "########## set timezone......."
  K8S_TIMEZONE=${K8S_TIMEZONE:-"Asia/Shanghai"}
  sudo timedatectl set-timezone "$K8S_TIMEZONE"
}

function enableTimeSync() {
  echo "########## enable time sync......."
  sudo systemctl enable systemd-timesyncd --now
}

function createAlias() {
  echo "########## create alias......."
  sed -i 's/#alias\s*ll.*$/alias ll="ls -Al --color=auto"/' .bashrc
}

function setRootPassword() {
  echo "########## set root password......."
  K8S_ROOT_PASSWORD=${K8S_ROOT_PASSWORD:-"vagrant"}
  echo "root:$K8S_ROOT_PASSWORD" | sudo chpasswd
}

function closeSwap() {
  echo "########## close swap......."
  sudo swapoff -a
  sudo sed -ri 's/.*swap.*/#&/' /etc/fstab
}

function configSysctl() {
  echo "########## config sysctl......."
  # sysctl settings for kubernetes
  # 1. br_netfilter module
  # 2. nf_conntrack module
  # 3. ip_vs module
  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
nf_conntrack
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
EOF

  sudo systemctl restart systemd-modules-load

  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
  sudo sysctl --system

}

function enablePromisc() {
  echo "########## enable promisc......."
  K8S_INTERFACE=${K8S_INTERFACE:-"eth1"}
  sudo ip l set dev "$K8S_INTERFACE" promisc on
  # check if promisc is enabled
  if ! grep -q -e 'promi' /etc/network/interfaces; then
    sudo sed -i -e "/iface $K8S_INTERFACE .*\$/ a \\ \\ \\ \\ \\ \\ post-up /sbin/ip link set $K8S_INTERFACE promisc on" /etc/network/interfaces
  fi
}

function configAptMirror() {
  echo "########## changing apt mirror......."
  K8S_APT_MIRROR=${K8S_APT_MIRROR:-"http://mirrors.tuna.tsinghua.edu.cn/debian"}
  K8S_APT_MIRROR_SECURITY=${K8S_APT_MIRROR_SECURITY:-"http://mirrors.tuna.tsinghua.edu.cn/debian"}
  # sudo apt-get install -y apt-transport-https ca-certificates curl gpg
  sudo dpkg -i "$this_dir/files/apt-transport-https_2.6.1_all.deb"
  sudo sed -i "s#https\?://deb.debian.org/debian/#$K8S_APT_MIRROR#g" /etc/apt/sources.list
  if [ -n "${K8S_APT_MIRROR_SECURITY}" ]; then
    sudo sed -i "s#https\?://security.debian.org/debian-security#$K8S_APT_MIRROR_SECURITY#g" /etc/apt/sources.list
  fi
}

function configAptMirrorDockerCE() {
  echo "########## config docker source......."
  K8S_APT_MIRROR_DOCER_CE=${K8S_APT_MIRROR_DOCER_CE:-"https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian"}
  # Add Docker's official GPG key:
  sudo install -m 0755 -d /etc/apt/keyrings
  # sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  sudo cp "$this_dir/files/docker.asc" /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # add docker apt source
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $K8S_APT_MIRROR_DOCER_CE \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
}

function configAptMirrorK8s() {
  echo "########## config k8s source......."
  K8S_APT_MIRROR_K8S=${K8S_APT_MIRROR_K8S:-"https://mirrors.tuna.tsinghua.edu.cn/kubernetes/core:/stable:/v1.30/deb/"}
  # add kubernetes apt source
  # curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg "$this_dir/files/k8s.key"
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] $K8S_APT_MIRROR_K8S /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
}

function aptUpdate() {
  echo "########## apt update......."
  sudo apt-get -y update
}

function installAllPackages() {
  echo "########## install all packages......."
  # sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo apt-get install -y ipset ipvsadm containerd.io nfs-common kubelet kubeadm kubectl
  sudo apt-mark hold kubelet kubeadm kubectl
  sudo systemctl enable --now kubelet
}

function configContainerdDefaults() {
  echo "########## config containerd defaults......."
  K8S_REGISTRY_GOOGLE=${K8S_REGISTRY_GOOGLE:-"registry.aliyuncs.com/google_containers"}
  K8S_PAUSE_VERSION=${K8S_PAUSE_VERSION:-"3.9"}
  # containerd config ,
  # 1. enable cri plugin 
  # 2. use systemd for cgroup
  # 3. modify sandbox_image default is "registry.k8s.io/pause:3.9"
  sudo mkdir -p /etc/containerd
  sudo containerd config default | sudo tee /etc/containerd/config.toml
  sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
  sudo sed -i "s#    sandbox_image =.*\$#    sandbox_image = \"$K8S_REGISTRY_GOOGLE/pause:${K8S_PAUSE_VERSION}\"#" /etc/containerd/config.toml
  sudo sed -i '/    \[plugins\."io.containerd.grpc.v1.cri"\.registry\]/{n;s/      config_path.*$/      config_path = "\/etc\/containerd\/certs.d"/}' /etc/containerd/config.toml
}

function configDockerIOMirrors() {
  echo "########## config docker.io mirrors......."
  if [ -z "${K8S_REGISTRY_DOCKER_IO}" ]; then
    echo "no docker.io mirrors"
    return
  fi
  
  IFS=','
  read -r -a mirrors <<<"$K8S_REGISTRY_DOCKER_IO"
  unset IFS

  if [ ${#mirrors[@]} -eq 0 ]; then
    echo "no docker.io mirrors"
    return
  fi
  sudo mkdir -p /etc/containerd/certs.d/docker.io/

  # local hosts_toml='server = "https://docker.io"'
  local hosts_toml=''
  for mirror in "${mirrors[@]}"; do
    hosts_toml="${hosts_toml}\n"
    hosts_toml="${hosts_toml}\n[host.\"${mirror}\"]"
    hosts_toml="${hosts_toml}\n  capabilities = [\"pull\", \"resolve\"]"
    if [[ "$mirror" =~ ^http: ]]; then
      hosts_toml="${hosts_toml}\n  skip_verify = true"
    fi
  done
  echo -e "$hosts_toml" | sudo tee /etc/containerd/certs.d/docker.io/hosts.toml
}

function configPrivateRegistry() {
  echo "########## config private registry......."
  # quit if no private registry
  if [ -z "${K8S_REGISTRY_PRIVATE}" ]; then
    echo "no private registry"
    return
  fi
  sudo mkdir -p "/etc/containerd/certs.d/$K8S_REGISTRY_PRIVATE"
  local host ca
  if [ -z "${K8S_REGISTRY_PRIVATE_CERT_FILE}" ]; then
    host="http://${K8S_REGISTRY_PRIVATE}"
  else
    host="https://${K8S_REGISTRY_PRIVATE}"
    ca="/etc/containerd/certs.d/${K8S_REGISTRY_PRIVATE}/ca.crt"
  fi
  local hosts_toml
  hosts_toml="server = \"$host\""
  hosts_toml="${hosts_toml}\n"
  hosts_toml="${hosts_toml}\n[host.\"${host}\"]"
  hosts_toml="${hosts_toml}\n  capabilities = [\"pull\", \"resolve\"]"
  if [ -n "${ca}" ]; then
    hosts_toml="${hosts_toml}\n  ca = \"${ca}\""
    sudo cp "${K8S_REGISTRY_PRIVATE_CERT_FILE}" "/etc/containerd/certs.d/${K8S_REGISTRY_PRIVATE}/ca.crt"
  else
    hosts_toml="${hosts_toml}\n  skip_verify = true"
  fi
  echo -e "$hosts_toml" | sudo tee "/etc/containerd/certs.d/${K8S_REGISTRY_PRIVATE}/hosts.toml"
}


function configContainerd() {
  echo "########## config containerd......."
  configContainerdDefaults

  configDockerIOMirrors

  configPrivateRegistry

  sudo systemctl restart containerd
}

function configDockerCE() {
  echo "########## config docker......."
  # docker加速配置
  sudo mkdir -p /etc/docker
  sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://ujk0k43n.mirror.aliyuncs.com"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  }
}
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart docker
}

function configCrictl() {
  echo "########## config crictl......."
  sudo tee /etc/crictl.yaml <<-'EOF'
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 0
debug: false
EOF
}

# function kubeadmInitSinaleMaster() {
#   echo "########## kubeadm init......."
#   if [ -z "${K8S_VERSION}" ]; then
#     echo "no k8s version, exit"
#     exit 1
#   fi
#   K8S_REGISTRY_GOOGLE=${K8S_REGISTRY_GOOGLE:-"registry.aliyuncs.com/google_containers"}
#   K8S_POD_NETWORK_CIDR=${K8S_POD_NETWORK_CIDR:-"10.244.0.0/16"}
#   sudo kubeadm init \
#     --apiserver-advertise-address="$(getIp)" \
#     --image-repository "$K8S_REGISTRY_GOOGLE" \
#     --pod-network-cidr="$K8S_POD_NETWORK_CIDR" \
#     --kubernetes-version "${K8S_VERSION}" \
#     --token-ttl 8760h
# }
function kubeadmInitSinaleMaster() {
  echo "########## kubeadm init......."
  if [ -z "${K8S_VERSION}" ]; then
    echo "no k8s version, exit"
    exit 1
  fi
  
  K8S_REGISTRY_GOOGLE=${K8S_REGISTRY_GOOGLE:-"registry.aliyuncs.com/google_containers"}
  K8S_POD_NETWORK_CIDR=${K8S_POD_NETWORK_CIDR:-"10.244.0.0/16"}
  K8S_APISERVER_ADVERTISE_ADDRESS=$(getIp)
  K8S_COTNROL_PLANE_ENDPOINT="${K8S_APISERVER_ADVERTISE_ADDRESS}:6443"

  export K8S_APISERVER_ADVERTISE_ADDRESS
  export K8S_VERSION
  export K8S_COTNROL_PLANE_ENDPOINT
  export K8S_POD_NETWORK_CIDR
  export K8S_REGISTRY_GOOGLE
  
 envsubst < "$this_dir/files/kubeadm-config.yml.template" > kubeadm-config.yml
  sudo kubeadm init --config=kubeadm-config.yml
}

function specifyApiBindAddress() {
  sudo sed -i "/--advertise-address/ a \ \ \ \ - --bind-address=$(getIp)" /etc/kubernetes/manifests/kube-apiserver.yaml
  sudo systemctl restart kubelet
}

function kubeadmInitFirstMaster() {
  echo "########## kubeadm init......."
  if [ -z "${K8S_VERSION}" ]; then
    echo "no k8s version, exit"
    exit 1
  fi
  K8S_REGISTRY_GOOGLE=${K8S_REGISTRY_GOOGLE:-"registry.aliyuncs.com/google_containers"}
  K8S_POD_NETWORK_CIDR=${K8S_POD_NETWORK_CIDR:-"10.244.0.0/16"}
  K8S_APISERVER_ADVERTISE_ADDRESS=$(getIp)

  export K8S_APISERVER_ADVERTISE_ADDRESS
  export K8S_VERSION
  export K8S_COTNROL_PLANE_ENDPOINT
  export K8S_POD_NETWORK_CIDR
  export K8S_REGISTRY_GOOGLE
  envsubst < "$this_dir/files/kubeadm-config.yml.template" > kubeadm-config.yml

  sudo kubeadm init --config=kubeadm-config.yml --upload-certs


  specifyApiBindAddress
}
# function kubeadmInitFirstMaster() {
#   echo "########## kubeadm init......."
#   if [ -z "${K8S_VERSION}" ]; then
#     echo "no k8s version, exit"
#     exit 1
#   fi
#   K8S_REGISTRY_GOOGLE=${K8S_REGISTRY_GOOGLE:-"registry.aliyuncs.com/google_containers"}
#   K8S_POD_NETWORK_CIDR=${K8S_POD_NETWORK_CIDR:-"10.244.0.0/16"}
#   sudo kubeadm init \
#     --apiserver-advertise-address="$(getIp)" \
#     --image-repository "$K8S_REGISTRY_GOOGLE" \
#     --pod-network-cidr="$K8S_POD_NETWORK_CIDR" \
#     --kubernetes-version "${K8S_VERSION}" \
#     --control-plane-endpoint="${K8S_COTNROL_PLANE_ENDPOINT}" \
#     --upload-certs

#   specifyApiBindAddress
# }

function exportKubeConfig() {
  echo "########## cp kube config......."
  mkdir -p "$HOME/.kube"
  sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  mkdir -p /vagrant/.tmp
  cp "$HOME/.kube/config" /vagrant/.tmp/config
}

function configKubectl() {
  echo "########## config kubectl......."
  mkdir -p "$HOME/.kube"
  cp /vagrant/.tmp/config "$HOME/.kube/config" 
}

function installFlannel() {
  echo "########## install flannel......."
  kubectl apply -f "$this_dir/files/kube-flannel.yml"
}

# $1: kubeadm join output file
function exportJoinWorkerScript() {
  echo "########## export join worker script......."
  # extract join worker command
  grep -A 3 'join any number of worker nodes' "$1" | sed -n '3,4p' >/vagrant/.tmp/join-worker.sh
  chmod +x /vagrant/.tmp/join-worker.sh
}

# $1: kubeadm join output file
function exportJoinMasterScript() {
  echo "########## export join script......."
  # extract join master command
  grep -A 4 'join any number of the control-plane node' "$1" | sed -n '3,5p' >/vagrant/.tmp/join-master.sh
  chmod +x /vagrant/.tmp/join-master.sh
}

function configNodeIp() {
  echo "########## config master node ip......."
  echo "KUBELET_EXTRA_ARGS='--node-ip=$(getIp)'" | sudo tee /etc/default/kubelet
  sudo systemctl restart kubelet
}

function joinMaster() {
  # join master
  echo "join control-plane master......"
  join_cmd="sudo $(cat /vagrant/.tmp/join-master.sh) --apiserver-advertise-address $(getIp) "
  eval "$join_cmd"

  specifyApiBindAddress
}

function joinWorker() {
  # join master
  echo "join master......"
  sudo /vagrant/.tmp/join-worker.sh
}

function configKubeletImageGC() {
  echo "########## config kubelet image gc......."
  if [ -z "${K8S_IMAGE_MINIMUM_GC_AGE}" ] ||  [ -z "${K8S_IMAGE_MAXIMUM_GC_AGE}" ]; then
    echo "no image gc config, skip"
    return
  fi
  sudo sed -i "s/^imageMaximumGCAge.*\$/imageMaximumGCAge: ${K8S_IMAGE_MAXIMUM_GC_AGE}/" /var/lib/kubelet/config.yaml
  sudo sed -i "s/^imageMinimumGCAge.*\$/imageMinimumGCAge: ${K8S_IMAGE_MINIMUM_GC_AGE}/" /var/lib/kubelet/config.yaml
  sudo systemctl restart kubelet
}

function installNginx() {
  echo "########## install nginx......."
  sudo apt-get install -y nginx-full
  if sudo grep -e "k8s-control-plane" /etc/nginx/nginx.conf; then
    echo "k8s has configed"
    return
  fi
  
  VM_MASTER_START=${VM_MASTER_START:-30}
  local SERVERS=""
  for i in $(seq 1 "$MASTER_COUNT"); do
    SERVERS+="        server ${VM_IP_PREFIX}.$((i - 1 + VM_MASTER_START)):6443;"$'\n'
  done
  local PORT=$(echo $K8S_COTNROL_PLANE_ENDPOINT | cut -d: -f2)
  
  cat <<EOF | sudo tee -a /etc/nginx/nginx.conf
stream {
    upstream k8s-control-plane {
        least_conn;
$SERVERS
    }
    server {
        listen $PORT;
        proxy_pass k8s-control-plane;
    }
}
EOF

  sudo systemctl reload nginx
}

function installKeepalived() {
  echo "########## install keepalived......."
  sudo apt-get install -y keepalived
  export KA_HOSTNAME=$(hostname)
  export K8S_INTERFACE=${K8S_INTERFACE:-"eth1"}
  export KA_PRIORITY=$((100 + ($2 - $1) * 10))
  export KA_STATE
  export KA_PREEMPT
  export K8S_COTNROL_PLANE_ENDPOINT_IP=$(echo "$K8S_COTNROL_PLANE_ENDPOINT" | cut -d: -f1)
  echo $1
  if [ "$1" -eq 1 ]; then
    KA_STATE="MASTER"
    KA_PREEMPT=""
  else
    KA_STATE="BACKUP"
    KA_PREEMPT="nopreempt"
  fi

  envsubst < "$this_dir/files/keepalived.conf.template" | sudo tee  /etc/keepalived/keepalived.conf

  sudo systemctl enable --now keepalived
}