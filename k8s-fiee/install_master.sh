#!/bin/bash
# Author: Alvaro Juscamayta (FIEE-UNAC), based on N.Saha
# Description: Worker Node Installation - using KVM IP of the worker1 VM
# ==============================================================================

WORKING_DIR="$(pwd)"

# --- FUNCIONES DE ESTILO ---
print_header() { echo -e "\n\e[1;34m############################### $1 ###############################\e[0m"; }
print_subheader() { echo -e "\e[1;36m--- $1 ---\e[0m"; }
print_success() { echo -e "\e[1;32m$1\e[0m"; }
print_info() { echo -e "\e[1;33mINFO: $1\e[0m"; }
print_error() { echo -e "\e[1;31mERROR: $1\e[0m"; }

# --- FASE 1: System preparation ---
prepare_system() {
    print_header "FASE 1/4: PREPARACIÓN DEL SISTEMA"
    sudo apt-get update -qq
    sudo apt-get install -y vim git curl iproute2 iputils-ping jq openvswitch-switch -qq
    
    print_subheader "Desactivando Swap y Firewall"
    sudo swapoff -a
    sudo sed -i '/swap/ s/^/#/' /etc/fstab
    sudo ufw disable

    print_subheader "Cargando Módulos del Kernel (Overlay & OVS)"
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
openvswitch
vxlan
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter
    sudo modprobe openvswitch
    
    print_subheader "Configurando Sysctl para Networking"
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    sudo sysctl --system &>/dev/null
}

# --- FASE 2: Containerd Installation---
install_containerd() {
    print_header "FASE 2/4: INSTALANDO CONTAINERD"
    sudo apt-get install -y ca-certificates gnupg containerd -qq
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd &>/dev/null
}

# --- FASE 3: OVS CNI Infraestructure ---
setup_ovs_worker() {
    print_header "FASE 3/4: INFRAESTRUCTURA OVS CNI"
    
    print_subheader "Creando Puentes OVS (N2, N3, N4)"
    sudo ovs-vsctl --may-exist add-br n2br
    sudo ovs-vsctl --may-exist add-br n3br
    sudo ovs-vsctl --may-exist add-br n4br

    print_subheader "Instalando Plugin Binario OVS-CNI"
    curl -L "https://github.com/k8snetworkplumbingwg/ovs-cni/releases/download/v0.31.0/ovs" -o /tmp/ovs
    sudo mkdir -p /opt/cni/bin
    sudo mv /tmp/ovs /opt/cni/bin/
    sudo chmod +x /opt/cni/bin/ovs
    print_success "Binario OVS-CNI listo en /opt/cni/bin/ovs"
}

# --- FASE 4: Kubernetes Installation ---
install_k8s_worker() {
    print_header "FASE 4/4: KUBERNETES WORKER COMPONENTS"
    
    # Instalación v1.28.15 para paridad con el Master
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -qq
    sudo apt-get install -y kubelet kubeadm kubectl -qq
    sudo apt-mark hold kubelet kubeadm kubectl

    # DETECCIÓN AUTOMÁTICA DE LA IP EN ENP1S0
    NODE_IP=$(ip -4 addr show enp1s0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    
    if [ -z "$NODE_IP" ]; then
        print_error "No se pudo detectar IP en enp1s0. Verifica el nombre de la interfaz."
    else
        print_info "IP Detectada en enp1s0: $NODE_IP"
        echo "KUBELET_EXTRA_ARGS=\"--node-ip=$NODE_IP\"" | sudo tee /etc/default/kubelet
        sudo systemctl daemon-reload
        sudo systemctl restart kubelet
    fi
}

main() {
    print_header "INICIANDO INSTALACIÓN DE NODO WORKER - FIEE UNAC"
    prepare_system
    install_containerd
    setup_ovs_worker
    install_k8s_worker
    
    print_header "WORKER LISTO"
    print_success "El nodo está preparado para unirse al clúster k8s-FIEE-UNAC."
    print_info "Ejecuta en el MASTER: el script de token"
    print_info "Luego pega ese comando aquí con 'sudo'."
}

main "$@"

