#!/bin/bash
# Author: Alvaro Juscamayta , basado en N.Saha
# Description: Instalación K8s-FIEE -Node-IP Bridge
# ==============================================================================

WORKING_DIR="$(pwd)"

# --- FUNCIONES DE ESTILO (SAHA-STYLE) ---
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
    echo -e "\e[1;31mERROR: $1\e[0m"
}

print_info() {
    echo -e "\e[1;33mINFO: $1\e[0m"
}

# --- VALIDACIONES Y PREPARACIÓN ---
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "Este script NO debe ejecutarse como root. Usa tu usuario alvaro."
        exit 1
    fi
}

prepare_node() {
    print_header "PREPARANDO NODO (FASE 1/5)"
    print_subheader "Desactivando Swap y Firewall"
    sudo swapoff -a
    sudo sed -i '/swap/ s/^/#/' /etc/fstab
    sudo ufw disable

    print_subheader "Cargando Módulos del Kernel"
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter

    print_subheader "Configurando Sysctl para Networking"
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    sudo sysctl --system &>/dev/null
}

# --- INSTALACIÓN DE BINARIOS ---
install_components() {
    print_header "INSTALANDO COMPONENTES (FASE 2/5)"
    
    print_subheader "Instalando Containerd.io"
    sudo apt-get update -qq && sudo apt-get install -y ca-certificates curl gnupg containerd -qq
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd &>/dev/null

    print_subheader "Instalando K8s v1.28.15"
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -qq
    sudo apt-get install -y kubelet kubeadm kubectl -qq
    sudo apt-mark hold kubelet kubeadm kubectl

    # --- CORRECCIÓN DE IP INTERNA (FORZAR BRIDGE) ---
    print_subheader "Configurando Kubelet para usar Bridge 192.168.122.1"
    echo 'KUBELET_EXTRA_ARGS="--node-ip=192.168.122.1"' | sudo tee /etc/default/kubelet
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
}

# --- INICIALIZACIÓN DEL CLÚSTER ---
init_cluster() {
    print_header "INICIALIZANDO CLÚSTER K8S (FASE 3/5)"
    
    if [ ! -f "kubeadm-config.yaml" ]; then
        print_error "Falta kubeadm-config.yaml en $WORKING_DIR"
        exit 1
    fi

    print_info "Realizando Pre-pull de imágenes (Estrategia 0 Restarts)..."
    sudo kubeadm config images pull --config kubeadm-config.yaml

    if sudo kubeadm init --config kubeadm-config.yaml --ignore-preflight-errors=all; then
        mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
        print_success "Control Plane iniciado correctamente."
    else
        print_error "Fallo en kubeadm init."
        exit 1
    fi
}

# --- CONFIGURACIÓN DE RED 5G ---
setup_networking() {
    print_header "CONFIGURANDO REDES 5G (FASE 4/5)"
    
    print_subheader "Aplicando Flannel (Pod Network)"
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    
    print_subheader "Aplicando Multus CNI (Secondary Interfaces)"
    kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
    
    print_subheader "Habilitando Nodo Master (Untaint)"
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null
}

# --- STORAGE PERSISTENTE ---
setup_storage() {
    print_header "CONFIGURANDO STORAGE PERSISTENTE (FASE 5/5)"
    
    print_subheader "Instalando Helm 3"
    if ! command -v helm &> /dev/null; then
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    print_subheader "Instalando OpenEBS para Base de Datos 5G"
    helm repo add openebs https://openebs.github.io/charts
    helm repo update
    helm upgrade --install openebs --namespace openebs openebs/openebs --create-namespace
    
    print_info "Esperando estabilización de Storage..."
    sleep 10
    
    print_subheader "Configurando openebs-hostpath como Default Class"
    kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
}

# --- FLUJO PRINCIPAL ---
main() {
    check_root
    print_header "DESPLIEGUE INICIADO - LABORATORIO K8S-FIEE"
    
    prepare_node
    install_components
    init_cluster
    setup_networking
    setup_storage
    
    print_header "DESPLIEGUE FINALIZADO EXITOSAMENTE"
    print_success "Estado del Clúster (Verifica INTERNAL-IP):"
    kubectl get nodes -o wide
    print_success "Storage Classes:"
    kubectl get sc
}

main "$@"
