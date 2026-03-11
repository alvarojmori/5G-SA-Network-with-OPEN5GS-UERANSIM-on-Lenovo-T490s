#!/usr/bin/env bash
# Author: Alvaro Juscamayta, based on N.Saha
# Description: K8S-FIEE UNAC master/control-plane installation on alvarolap

set -euo pipefail

WORKING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MASTER_NODE_NAME="${MASTER_NODE_NAME:-$(hostname -s)}"
MASTER_NODE_IP="${MASTER_NODE_IP:-192.168.122.1}"
MASTER_BRIDGE_IF="${MASTER_BRIDGE_IF:-virbr0}"
K8S_CHANNEL="${K8S_CHANNEL:-v1.28}"
PAUSE_IMAGE="${PAUSE_IMAGE:-registry.k8s.io/pause:3.9}"
FLANNEL_IFACE_REGEX="${FLANNEL_IFACE_REGEX:-^(virbr0|enp1s0)$}"

FLANNEL_MANIFEST_URL="${FLANNEL_MANIFEST_URL:-https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml}"
MULTUS_MANIFEST_URL="${MULTUS_MANIFEST_URL:-https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml}"
CNAO_NAMESPACE_URL="${CNAO_NAMESPACE_URL:-https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.101.0-rc-0/namespace.yaml}"
CNAO_CRD_URL="${CNAO_CRD_URL:-https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.101.0-rc-0/network-addons-config.crd.yaml}"
CNAO_OPERATOR_URL="${CNAO_OPERATOR_URL:-https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.101.0-rc-0/operator.yaml}"

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
    require_cmd mktemp
}

validate_master_network() {
    print_header "VALIDANDO RED DEL MASTER"

    if ! ip link show "${MASTER_BRIDGE_IF}" >/dev/null 2>&1; then
        print_error "La interfaz ${MASTER_BRIDGE_IF} no existe."
        exit 1
    fi

    if ! ip -4 -o addr show dev "${MASTER_BRIDGE_IF}" | grep -q "${MASTER_NODE_IP}/"; then
        print_error "La interfaz ${MASTER_BRIDGE_IF} no tiene la IP ${MASTER_NODE_IP}."
        ip -4 -o addr show dev "${MASTER_BRIDGE_IF}" || true
        exit 1
    fi

    print_success "Interfaz ${MASTER_BRIDGE_IF} validada con IP ${MASTER_NODE_IP}"
}

validate_kubeadm_config() {
    print_header "VALIDANDO kubeadm-config.yaml"

    local cfg="${WORKING_DIR}/kubeadm-config.yaml"

    if [[ ! -f "${cfg}" ]]; then
        print_error "Falta kubeadm-config.yaml en ${WORKING_DIR}"
        exit 1
    fi

    grep -q "${MASTER_NODE_IP}" "${cfg}" || {
        print_error "kubeadm-config.yaml no contiene ${MASTER_NODE_IP}."
        exit 1
    }

    grep -q "10.244.0.0/16" "${cfg}" || {
        print_error "kubeadm-config.yaml no contiene podSubnet 10.244.0.0/16."
        exit 1
    }

    print_success "kubeadm-config.yaml validado"
}

prepare_node() {
    print_header "PREPARANDO NODO (FASE 1/6)"

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

    print_success "Nodo preparado"
}

install_components() {
    print_header "INSTALANDO COMPONENTES BASE (FASE 2/6)"

    print_subheader "Instalando containerd + Open vSwitch"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        apt-transport-https \
        containerd \
        openvswitch-switch

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

    print_subheader "Configurando kubelet con Node-IP fijo del bridge"
    echo "KUBELET_EXTRA_ARGS=\"--node-ip=${MASTER_NODE_IP}\"" | sudo tee /etc/default/kubelet >/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable kubelet
    sudo systemctl restart kubelet

    print_success "Componentes base instalados"
}

setup_ovs_infrastructure() {
    print_header "CONFIGURANDO INFRAESTRUCTURA OVS CNI (FASE 3/6)"

    print_subheader "Creando bridges OVS N2/N3/N4"
    sudo ovs-vsctl --may-exist add-br n2br
    sudo ovs-vsctl --may-exist add-br n3br
    sudo ovs-vsctl --may-exist add-br n4br

    print_subheader "Instalando binario ovs-cni"
    sudo mkdir -p /opt/cni/bin
    curl -fsSL "https://github.com/k8snetworkplumbingwg/ovs-cni/releases/download/v0.31.0/ovs" -o /tmp/ovs
    sudo mv /tmp/ovs /opt/cni/bin/ovs
    sudo chmod +x /opt/cni/bin/ovs

    print_success "OVS y ovs-cni preparados"
}

wait_for_apiserver() {
    print_subheader "Esperando estabilización del API server"

    local tries=90
    local i

    for ((i=1; i<=tries; i++)); do
        if kubectl get --raw='/readyz' >/dev/null 2>&1; then
            print_success "API server responde correctamente"
            return 0
        fi
        sleep 2
    done

    print_error "El API server no quedó listo a tiempo"
    kubectl get pods -n kube-system -o wide || true
    sudo crictl ps -a || true
    exit 1
}

init_cluster() {
    print_header "INICIALIZANDO CLÚSTER K8S (FASE 4/6)"

    print_subheader "Pre-pull de imágenes"
    sudo kubeadm config images pull --config "${WORKING_DIR}/kubeadm-config.yaml"

    print_subheader "Inicializando control-plane"
    sudo kubeadm init --config "${WORKING_DIR}/kubeadm-config.yaml"

    print_subheader "Configurando kubeconfig para el usuario"
    mkdir -p "${HOME}/.kube"
    sudo cp /etc/kubernetes/admin.conf "${HOME}/.kube/config"
    sudo chown "$(id -u)":"$(id -g)" "${HOME}/.kube/config"

    wait_for_apiserver

    print_subheader "Validando binarios"
    kubectl version --client || true
    kubeadm version -o short || true

    print_success "Control-plane inicializado correctamente"
}

download_flannel_manifest() {
    local tmpfile
    tmpfile="$(mktemp /tmp/kube-flannel.XXXXXX.yaml)"

    print_subheader "Descargando manifiesto Flannel a archivo temporal" >&2
    curl -fsSL "${FLANNEL_MANIFEST_URL}" -o "${tmpfile}"

    print_subheader "Inyectando --iface-regex=${FLANNEL_IFACE_REGEX} en manifiesto Flannel" >&2

    if grep -q -- "--iface-regex=" "${tmpfile}"; then
        sed -i "s#- --iface-regex=.*#        - --iface-regex=${FLANNEL_IFACE_REGEX}#g" "${tmpfile}"
    elif grep -q -- "--iface=" "${tmpfile}"; then
        sed -i "s#- --iface=.*#        - --iface-regex=${FLANNEL_IFACE_REGEX}#g" "${tmpfile}"
    else
        sed -i "/- --kube-subnet-mgr/a\        - --iface-regex=${FLANNEL_IFACE_REGEX}" "${tmpfile}"
    fi

    printf '%s\n' "${tmpfile}"
}

apply_manifest_with_retries() {
    local manifest="$1"
    local description="$2"
    local retries="${3:-20}"
    local sleep_seconds="${4:-5}"
    local i

    for ((i=1; i<=retries; i++)); do
        print_info "Aplicando ${description} (intento ${i}/${retries})"
        if kubectl apply -f "${manifest}"; then
            print_success "${description} aplicado correctamente"
            return 0
        fi
        sleep "${sleep_seconds}"
    done

    print_error "No se pudo aplicar ${description} después de ${retries} intentos"
    exit 1
}

wait_for_daemonset() {
    local ns="$1"
    local ds="$2"
    local timeout="${3:-180}"
    local waited=0

    until kubectl -n "${ns}" get ds "${ds}" >/dev/null 2>&1; do
        sleep 2
        waited=$((waited + 2))
        if [[ "${waited}" -ge "${timeout}" ]]; then
            print_error "Timeout esperando DaemonSet ${ds} en namespace ${ns}"
            exit 1
        fi
    done
}

wait_for_node_ready() {
    print_subheader "Esperando que el nodo master pase a Ready"

    local tries=120
    local i

    for ((i=1; i<=tries; i++)); do
        if kubectl get node "${MASTER_NODE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            print_success "Nodo ${MASTER_NODE_NAME} está Ready"
            return 0
        fi
        sleep 2
    done

    print_error "El nodo ${MASTER_NODE_NAME} no pasó a Ready a tiempo"
    kubectl describe node "${MASTER_NODE_NAME}" || true
    exit 1
}

setup_networking() {
    print_header "CONFIGURANDO REDES 5G & MULTUS (FASE 5/6)"

    local flannel_manifest
    flannel_manifest="$(download_flannel_manifest)"

    apply_manifest_with_retries "${flannel_manifest}" "Flannel" 20 5
    wait_for_daemonset "kube-flannel" "kube-flannel-ds" 180

    print_subheader "Esperando rollout de Flannel"
    kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=240s

    wait_for_node_ready

    print_subheader "Habilitando scheduling en control-plane"
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

    print_subheader "Aplicando Multus CNI (Thick Mode)"
    apply_manifest_with_retries "${MULTUS_MANIFEST_URL}" "Multus" 20 5
    wait_for_daemonset "kube-system" "kube-multus-ds" 180
    kubectl rollout status daemonset/kube-multus-ds -n kube-system --timeout=240s || true

    print_subheader "Instalando Cluster Network Addons Operator"
    apply_manifest_with_retries "${CNAO_NAMESPACE_URL}" "CNAO namespace" 20 5
    apply_manifest_with_retries "${CNAO_CRD_URL}" "CNAO CRD" 20 5
    apply_manifest_with_retries "${CNAO_OPERATOR_URL}" "CNAO operator" 20 5

    rm -f "${flannel_manifest}"

    print_success "Red base del clúster desplegada"
}

setup_storage() {
    print_header "CONFIGURANDO STORAGE PERSISTENTE (FASE 6/6)"

    if ! command -v helm >/dev/null 2>&1; then
        print_subheader "Instalando Helm 3"
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    print_subheader "Instalando OpenEBS"
    helm repo add openebs https://openebs.github.io/charts >/dev/null 2>&1 || true
    helm repo update >/dev/null
    helm upgrade --install openebs --namespace openebs openebs/openebs --create-namespace

    print_subheader "Esperando StorageClass openebs-hostpath"
    local i
    for i in $(seq 1 60); do
        if kubectl get storageclass openebs-hostpath >/dev/null 2>&1; then
            kubectl patch storageclass openebs-hostpath \
              -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
            print_success "openebs-hostpath marcado como default"
            return
        fi
        sleep 2
    done

    print_error "No apareció openebs-hostpath dentro del tiempo esperado"
    exit 1
}

post_checks() {
    print_header "VALIDACIONES FINALES"

    print_subheader "Nodos"
    kubectl get nodes -o wide

    print_subheader "Pods del sistema"
    kubectl get pods -A

    print_subheader "Args efectivos de Flannel"
    kubectl -n kube-flannel get ds kube-flannel-ds -o jsonpath='{.spec.template.spec.containers[0].args}'
    echo

    print_success "Master instalado correctamente"
    print_info "Siguiente paso: ejecutar install_worker.sh en la VM worker"
}

main() {
    check_root
    validate_prereqs
    validate_master_network
    validate_kubeadm_config

    print_header "DESPLIEGUE INICIADO - LABORATORIO K8S-FIEE"

    prepare_node
    install_components
    setup_ovs_infrastructure
    init_cluster
    setup_networking
    setup_storage
    post_checks
}

main "$@"
