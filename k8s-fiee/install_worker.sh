#!/usr/bin/env bash
# Author: Alvaro Juscamayta, based on N.Saha
# Description: K8S-FIEE UNAC worker installation on VM worker node

set -euo pipefail

WORKING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_IF="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"

WORKER_NODE_NAME="${WORKER_NODE_NAME:-$(hostname -s)}"
WORKER_NODE_IF="${WORKER_NODE_IF:-${DEFAULT_IF:-enp1s0}}"
WORKER_NODE_IP="${WORKER_NODE_IP:-}"
K8S_CHANNEL="${K8S_CHANNEL:-v1.28}"
PAUSE_IMAGE="${PAUSE_IMAGE:-registry.k8s.io/pause:3.9}"
OVS_CNI_VERSION="${OVS_CNI_VERSION:-v0.31.0}"
CNI_PLUGINS_VERSION="${CNI_PLUGINS_VERSION:-v1.4.0}"

print_header() {
    echo -e "\n\e[1;34m############################### $1 ###############################\e[0m"
}

print_subheader() {
    echo -e "\e[1;36m--- $1 ---\e[0m"
}

print_success() {
    echo -e "\e[1;32m$1\e[0m"
}

print_error() {
    echo -e "\e[1;31mERROR: $1\e[0m" >&2
}

print_info() {
    echo -e "\e[1;33mINFO: $1\e[0m"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        print_error "No se encontró el comando requerido: $1"
        exit 1
    }
}

check_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        print_error "Este script NO debe ejecutarse como root. Usa tu usuario normal."
        exit 1
    fi
}

validate_prereqs() {
    print_header "VALIDANDO PRERREQUISITOS"
    require_cmd sudo
    require_cmd curl
    require_cmd ip
    require_cmd sed
    require_cmd awk
    require_cmd grep
    require_cmd tar
    require_cmd systemctl
}

detect_worker_network() {
    print_header "VALIDANDO RED DEL WORKER"

    if ! ip link show "${WORKER_NODE_IF}" >/dev/null 2>&1; then
        print_error "La interfaz ${WORKER_NODE_IF} no existe."
        ip link show || true
        exit 1
    fi

    if [[ -z "${WORKER_NODE_IP}" ]]; then
        WORKER_NODE_IP="$(ip -4 -o addr show dev "${WORKER_NODE_IF}" scope global | awk '{split($4,a,"/"); print a[1]; exit}')"
    fi

    if [[ -z "${WORKER_NODE_IP}" ]]; then
        print_error "No se pudo detectar una IPv4 en ${WORKER_NODE_IF}."
        ip -4 -o addr show dev "${WORKER_NODE_IF}" || true
        exit 1
    fi

    print_success "Interfaz ${WORKER_NODE_IF} validada con IP ${WORKER_NODE_IP}"
}

prepare_node() {
    print_header "PREPARANDO NODO WORKER (FASE 1/4)"

    print_subheader "Desactivando Swap"
    sudo swapoff -a
    sudo sed -ri 's@^([^#].*\sswap\s.*)$@# \1@g' /etc/fstab

    print_subheader "Desactivando UFW si existe"
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw disable || true
    else
        print_info "UFW no está instalado. Se omite."
    fi

    print_subheader "Cargando módulos del kernel base"
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
vxlan
openvswitch
EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter
    sudo modprobe vxlan
    sudo modprobe openvswitch || true

    print_subheader "Configurando sysctl"
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

    sudo sysctl -p /etc/sysctl.d/k8s.conf >/dev/null

    print_success "Nodo worker preparado"
}

install_components() {
    print_header "INSTALANDO COMPONENTES BASE (FASE 2/4)"

    print_subheader "Instalando paquetes base, containerd y Open vSwitch"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        jq \
        apt-transport-https \
        containerd \
        openvswitch-switch \
        iptables \
        netfilter-persistent \
        iptables-persistent

    print_subheader "Habilitando Open vSwitch"
    sudo systemctl enable --now openvswitch-switch
    sudo modprobe openvswitch || true

    print_subheader "Configurando containerd"
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    sudo sed -i "s#sandbox_image = .*#sandbox_image = \"${PAUSE_IMAGE}\"#g" /etc/containerd/config.toml
    sudo systemctl enable containerd
    sudo systemctl restart containerd

    print_subheader "Instalando Kubernetes ${K8S_CHANNEL}"
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/Release.key" \
      | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/ /" \
      | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl

    print_subheader "Configurando kubelet con Node-IP fijo"
    echo "KUBELET_EXTRA_ARGS=\"--node-ip=${WORKER_NODE_IP}\"" | sudo tee /etc/default/kubelet >/dev/null

    print_subheader "Asegurando que kubelet espere red completa antes de arrancar"
    sudo mkdir -p /etc/systemd/system/kubelet.service.d
    cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/10-wait-network.conf >/dev/null
[Unit]
After=network-online.target
Wants=network-online.target
EOF

    print_subheader "Aplicando reglas iptables base del worker"
    # Permite tráfico de vuelta al master (kubelet → API server)
    sudo iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
        || sudo iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    sudo iptables -C INPUT -p tcp --dport 10250 -j ACCEPT 2>/dev/null \
        || sudo iptables -I INPUT -p tcp --dport 10250 -j ACCEPT
    sudo iptables -C FORWARD -s 10.244.0.0/16 -j ACCEPT 2>/dev/null \
        || sudo iptables -I FORWARD -s 10.244.0.0/16 -j ACCEPT
    sudo iptables -C FORWARD -d 10.244.0.0/16 -j ACCEPT 2>/dev/null \
        || sudo iptables -I FORWARD -d 10.244.0.0/16 -j ACCEPT
    sudo netfilter-persistent save >/dev/null 2>&1 || true

    sudo systemctl daemon-reload
    sudo systemctl enable kubelet
    sudo systemctl restart kubelet

    print_success "Componentes base instalados"
}

setup_ovs_infrastructure() {
    print_header "CONFIGURANDO INFRAESTRUCTURA OVS + CNI (FASE 3/4)"

    print_subheader "Creando bridges OVS N2/N3/N4"
    sudo ovs-vsctl --may-exist add-br n2br
    sudo ovs-vsctl --may-exist add-br n3br
    sudo ovs-vsctl --may-exist add-br n4br

    print_subheader "Instalando plugins CNI estándar"
    sudo mkdir -p /opt/cni/bin
    curl -fsSL "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz" \
      -o /tmp/cni-plugins.tgz
    sudo tar -C /opt/cni/bin -xzf /tmp/cni-plugins.tgz
    rm -f /tmp/cni-plugins.tgz

    print_subheader "Instalando binario ovs-cni"
    curl -fsSL "https://github.com/k8snetworkplumbingwg/ovs-cni/releases/download/${OVS_CNI_VERSION}/ovs" -o /tmp/ovs
    sudo mv /tmp/ovs /opt/cni/bin/ovs
    sudo chmod +x /opt/cni/bin/ovs

    print_success "OVS y CNI del worker preparados"
}

post_checks() {
    print_header "VALIDACIONES FINALES (FASE 4/4)"

    print_subheader "Estado de servicios"
    sudo systemctl is-active containerd
    sudo systemctl is-active openvswitch-switch
    sudo systemctl is-active kubelet

    print_subheader "IP configurada del nodo"
    ip -4 -o addr show dev "${WORKER_NODE_IF}" || true

    print_subheader "Bridges OVS"
    sudo ovs-vsctl show || true

    print_subheader "Versiones"
    kubelet --version || true
    kubeadm version -o short || true
    kubectl version --client || true

    print_success "Worker instalado correctamente"
    print_info "Nodo: ${WORKER_NODE_NAME}"
    print_info "Interfaz usada: ${WORKER_NODE_IF}"
    print_info "Node IP: ${WORKER_NODE_IP}"
    print_info "Siguiente paso: ejecutar el kubeadm join generado desde el master"
}

main() {
    check_root
    validate_prereqs
    detect_worker_network

    print_header "DESPLIEGUE INICIADO - WORKER K8S-FIEE"

    prepare_node
    install_components
    setup_ovs_infrastructure
    post_checks
}

main "$@"
