#!/bin/bash
# Author: Alvaro Juscamayta (FIEE-UNAC)
# Description: Instalación de Nodo Worker1 - Detección automática de IP en Bridge
# ==============================================================================

# --- Funciones de Formato ---
print_header() { echo -e "\n\e[1;34m############################### $1 ###############################\e[0m"; }
print_subheader() { echo -e "\e[1;36m--- $1 ---\e[0m"; }
print_success() { echo -e "\e[1;32m$1\e[0m"; }
print_info() { echo -e "\e[1;33mINFO: $1\e[0m"; }

# --- FASE 1: Preparación ---
prepare_system() {
    print_header "FASE 1/3: PREPARACIÓN DEL SISTEMA"
    sudo apt-get update -qq
    sudo apt-get install -y vim git curl iproute2 iputils-ping jq openvswitch-switch -qq
    sudo swapoff -a
    sudo sed -i '/swap/ s/^/#/' /etc/fstab
    sudo ufw disable

    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter
    
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    sudo sysctl --system &>/dev/null
}

# --- FASE 2: Containerd ---
install_containerd() {
    print_header "FASE 2/3: INSTALANDO CONTAINERD"
    sudo apt-get install -y ca-certificates gnupg containerd -qq
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    sudo systemctl restart containerd
}

# --- FASE 3: K8s & Networking (Detección de IP) ---
install_k8s_and_ovs() {
    print_header "FASE 3/3: KUBERNETES & 5G NETWORKING"
    
    # Instalación v1.28.15
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -qq
    sudo apt-get install -y kubelet kubeadm kubectl -qq
    sudo apt-mark hold kubelet kubeadm kubectl

    # DETECCIÓN AUTOMÁTICA DE LA IP EN ENP1S0
    NODE_IP=$(ip -4 addr show enp1s0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    print_info "IP Detectada en enp1s0: $NODE_IP"

    # Forzar IP en Kubelet
    echo "KUBELET_EXTRA_ARGS=\"--node-ip=$NODE_IP\"" | sudo tee /etc/default/kubelet
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet

    # Puentes OVS para 5G
    sudo ovs-vsctl --may-exist add-br n2br
    sudo ovs-vsctl --may-exist add-br n3br
    sudo ovs-vsctl --may-exist add-br n4br
}

main() {
    prepare_system
    install_containerd
    install_k8s_and_ovs
    print_success "Worker1 listo. Usa la IP 192.168.122.1 para el 'kubeadm join'."
}

main "$@"
