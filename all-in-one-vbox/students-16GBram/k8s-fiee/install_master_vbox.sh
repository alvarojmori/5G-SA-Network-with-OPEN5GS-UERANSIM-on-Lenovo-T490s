#!/usr/bin/env bash
# Author: Alvaro Juscamayta, based on N.Saha
# Description: K8S-FIEE master/control-plane installation
# Adaptado para VirtualBox — NODO UNICO, IP 10.0.2.15
# Sin variable de bridge. Incluye plugins CNI base + OVS + Multus + OpenEBS.

set -euo pipefail

WORKING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Kubernetes registra el nodo SIEMPRE en minúsculas. Forzamos lowercase para que
# 'kubectl get node <name>' coincida (hostname -s puede traer mayúsculas, p.ej.
# wait_for_node_ready se cuelga aunque el nodo ya esté Ready.
MASTER_NODE_NAME="${MASTER_NODE_NAME:-$(hostname -s | tr '[:upper:]' '[:lower:]')}"
MASTER_NODE_IP="${MASTER_NODE_IP:-10.0.2.15}"          # IP de la VM en VirtualBox
K8S_CHANNEL="${K8S_CHANNEL:-v1.28}"
PAUSE_IMAGE="${PAUSE_IMAGE:-registry.k8s.io/pause:3.9}"
FLANNEL_IFACE_REGEX="${FLANNEL_IFACE_REGEX:-^enp0s3$}" # interfaz de la VM (solo para Flannel)

# Versiones de CNI
CNI_PLUGINS_VERSION="${CNI_PLUGINS_VERSION:-v1.4.0}"   # plugins base: loopback, bridge, host-local, portmap...
OVS_CNI_VERSION="${OVS_CNI_VERSION:-v0.31.0}"          # binario ovs-cni

FLANNEL_MANIFEST_URL="${FLANNEL_MANIFEST_URL:-https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml}"
MULTUS_MANIFEST_URL="${MULTUS_MANIFEST_URL:-https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml}"
CNAO_NAMESPACE_URL="${CNAO_NAMESPACE_URL:-https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.101.0-rc-0/namespace.yaml}"
CNAO_CRD_URL="${CNAO_CRD_URL:-https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.101.0-rc-0/network-addons-config.crd.yaml}"
CNAO_OPERATOR_URL="${CNAO_OPERATOR_URL:-https://github.com/kubevirt/cluster-network-addons-operator/releases/download/v0.101.0-rc-0/operator.yaml}"

print_header()    { echo -e "\n\e[1;34m############################### $1 ###############################\e[0m"; }
print_subheader() { echo -e "\e[1;36m--- $1 ---\e[0m"; }
print_success()   { echo -e "\e[1;32m$1\e[0m"; }
print_error()     { echo -e "\e[1;31mERROR: $1\e[0m" >&2; }
print_info()      { echo -e "\e[1;33mINFO: $1\e[0m"; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || { print_error "No se encontró el comando requerido: $1"; exit 1; }
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
    require_cmd tar
}

validate_master_network() {
    print_header "VALIDANDO RED DEL MASTER"

    if ! ip -4 -o addr show | grep -q "${MASTER_NODE_IP}/"; then
        print_error "Ninguna interfaz del host tiene la IP ${MASTER_NODE_IP}."
        ip -4 -o addr show || true
        exit 1
    fi

    print_success "IP ${MASTER_NODE_IP} encontrada en el host"
}

validate_kubeadm_config() {
    print_header "VALIDANDO kubeadm-config.yaml"

    local cfg="${WORKING_DIR}/kubeadm-config.yaml"

    [[ -f "${cfg}" ]] || { print_error "Falta kubeadm-config.yaml en ${WORKING_DIR}"; exit 1; }

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

    print_subheader "Forzando backend iptables-legacy (acelera kubeadm/kube-proxy)"
    # En Ubuntu reciente iptables usa nf_tables por defecto; en VMs con pocos
    # recursos las operaciones (ChainExists) tardan DECENAS de segundos y hacen
    # Legacy es mucho más rápido y deja el init en ~30s.
    if update-alternatives --list iptables 2>/dev/null | grep -q legacy; then
        sudo update-alternatives --set iptables  /usr/sbin/iptables-legacy  || true
        sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true
        sudo update-alternatives --set arptables /usr/sbin/arptables-legacy 2>/dev/null || true
        sudo update-alternatives --set ebtables  /usr/sbin/ebtables-legacy  2>/dev/null || true
        print_success "iptables -> legacy"
    else
        print_info "iptables-legacy no disponible; se mantiene el backend actual (nf_tables)."
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

wait_for_apt_lock() {
    # Ubuntu corre 'unattended-upgrades' al arrancar y toma el lock de dpkg/apt.
    # Esperamos a que se libere (hasta 5 min) para evitar el error
    # "No se pudo bloquear /var/lib/dpkg/lock-frontend" (caso de un compañero).
    local max=60 i=0
    while sudo fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock >/dev/null 2>&1; do
        i=$((i+1))
        if [[ "${i}" -gt "${max}" ]]; then
            print_error "El lock de apt/dpkg sigue ocupado tras 5 min. Ejecuta:"
            print_error "  sudo systemctl stop unattended-upgrades && sudo pkill -9 unattended-upgr"
            exit 1
        fi
        print_info "apt/dpkg ocupado (probablemente unattended-upgrades). Esperando... (${i}/${max})"
        sleep 5
    done
}

install_components() {
    print_header "INSTALANDO COMPONENTES BASE (FASE 2/6)"

    print_subheader "Instalando containerd + Open vSwitch + herramientas de red"
    wait_for_apt_lock
    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates curl gnupg apt-transport-https \
        containerd openvswitch-switch \
        iptables netfilter-persistent iptables-persistent

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

    wait_for_apt_lock
    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl

    print_subheader "Configurando kubelet con Node-IP fijo (${MASTER_NODE_IP})"
    echo "KUBELET_EXTRA_ARGS=\"--node-ip=${MASTER_NODE_IP}\"" | sudo tee /etc/default/kubelet >/dev/null

    print_subheader "Override de kubelet: esperar a la red (sin libvirtd)"
    sudo mkdir -p /etc/systemd/system/kubelet.service.d
    cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/10-wait-network.conf >/dev/null
[Unit]
After=network-online.target
Wants=network-online.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable kubelet
    sudo systemctl restart kubelet

    print_success "Componentes base instalados"
}

setup_ovs_infrastructure() {
    print_header "CONFIGURANDO INFRAESTRUCTURA CNI / OVS (FASE 3/6)"

    sudo mkdir -p /opt/cni/bin

    # >>> FIX: instalar plugins base de CNI (loopback, bridge, host-local, portmap...).
    #     Sin esto, el kubelet no puede crear ni el sandbox básico y el nodo nunca pasa a Ready.
    print_subheader "Instalando plugins base de CNI ${CNI_PLUGINS_VERSION}"
    curl -fsSL "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz" \
      | sudo tar -C /opt/cni/bin -xz

    print_subheader "Creando bridges OVS N2/N3/N4"
    sudo ovs-vsctl --may-exist add-br n2br
    sudo ovs-vsctl --may-exist add-br n3br
    sudo ovs-vsctl --may-exist add-br n4br

    print_subheader "Instalando binario ovs-cni ${OVS_CNI_VERSION}"
    curl -fsSL "https://github.com/k8snetworkplumbingwg/ovs-cni/releases/download/${OVS_CNI_VERSION}/ovs" -o /tmp/ovs
    sudo mv /tmp/ovs /opt/cni/bin/ovs
    sudo chmod +x /opt/cni/bin/ovs

    print_subheader "Verificando que los plugins clave estén presentes"
    for p in loopback bridge host-local portmap ovs; do
        if [[ -x "/opt/cni/bin/${p}" ]]; then
            print_info "  OK  /opt/cni/bin/${p}"
        else
            print_error "Falta el plugin /opt/cni/bin/${p}"
            exit 1
        fi
    done

    print_success "Plugins CNI base + OVS + ovs-cni preparados"
}

wait_for_apiserver() {
    print_subheader "Esperando estabilización del API server"
    local tries=90 i
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

apply_iptables_rules() {
    print_subheader "Aplicando reglas iptables para K8s"

    sudo iptables -C INPUT -p tcp --dport 6443 -j ACCEPT 2>/dev/null \
        || sudo iptables -I INPUT -p tcp --dport 6443 -j ACCEPT
    sudo iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
        || sudo iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    sudo iptables -C FORWARD -s 10.244.0.0/16 -j ACCEPT 2>/dev/null \
        || sudo iptables -I FORWARD -s 10.244.0.0/16 -j ACCEPT
    sudo iptables -C FORWARD -d 10.244.0.0/16 -j ACCEPT 2>/dev/null \
        || sudo iptables -I FORWARD -d 10.244.0.0/16 -j ACCEPT
    sudo iptables -C INPUT -p tcp --dport 10250 -j ACCEPT 2>/dev/null \
        || sudo iptables -I INPUT -p tcp --dport 10250 -j ACCEPT

    sudo netfilter-persistent save >/dev/null 2>&1 || true
    print_success "Reglas iptables aplicadas y persistidas"
}

# ── Sin bridge: verifica la IP del nodo en cualquier interfaz ──
ensure_node_network() {
    print_subheader "Verificando IP ${MASTER_NODE_IP} en el host"
    local waited=0
    until ip -4 -o addr show 2>/dev/null | grep -q "${MASTER_NODE_IP}/"; do
        sleep 2
        waited=$((waited + 2))
        if [[ "${waited}" -ge 30 ]]; then
            print_error "El host no tiene la IP ${MASTER_NODE_IP} tras 30s."
            exit 1
        fi
    done
    print_success "IP ${MASTER_NODE_IP} disponible"
}

init_cluster() {
    print_header "INICIALIZANDO CLÚSTER K8S (FASE 4/6)"

    ensure_node_network
    apply_iptables_rules

    # Si ya hay un control-plane inicializado de un intento previo, kubeadm
    # init falla con "Port 6443 in use / manifests already exist". Detectamos
    # ese estado y hacemos un reset limpio para poder reintentar sin trabarse.
    if [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]] || sudo ss -ltn 2>/dev/null | grep -q ':6443'; then
        print_info "Se detectó un control-plane previo. Haciendo 'kubeadm reset' para empezar limpio..."
        sudo kubeadm reset -f || true
        sudo rm -rf /etc/kubernetes /var/lib/etcd /etc/cni/net.d "${HOME}/.kube"
        sudo systemctl restart containerd kubelet 2>/dev/null || true
        sleep 5
    fi

    print_subheader "Pre-pull de imágenes"
    sudo kubeadm config images pull --config "${WORKING_DIR}/kubeadm-config.yaml"

    print_subheader "Inicializando control-plane"
    # --ignore-preflight-errors=NumCPU: VMs con 1 CPU (kubeadm exige 2). Se
    # permite continuar; recomendado 2-4 CPU para que no haya 'flapping'.
    sudo kubeadm init --config "${WORKING_DIR}/kubeadm-config.yaml" \
        --ignore-preflight-errors=NumCPU

    print_subheader "Configurando kubeconfig (apuntando a 127.0.0.1)"
    mkdir -p "${HOME}/.kube"
    sudo sed "s|https://${MASTER_NODE_IP}:6443|https://127.0.0.1:6443|g" \
        /etc/kubernetes/admin.conf > "${HOME}/.kube/config"
    chmod 600 "${HOME}/.kube/config"

    wait_for_apiserver

    kubectl version --client || true
    kubeadm version -o short || true

    print_success "Control-plane inicializado correctamente"
}

download_flannel_manifest() {
    local tmpfile
    tmpfile="$(mktemp /tmp/kube-flannel.XXXXXX.yaml)"

    print_subheader "Descargando manifiesto Flannel" >&2
    curl -fsSL "${FLANNEL_MANIFEST_URL}" -o "${tmpfile}"

    print_subheader "Inyectando --iface-regex=${FLANNEL_IFACE_REGEX}" >&2
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
    local manifest="$1" description="$2" retries="${3:-20}" sleep_seconds="${4:-5}" i
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
    local ns="$1" ds="$2" timeout="${3:-180}" waited=0
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
    print_subheader "Esperando que el nodo pase a Ready"
    local tries=300 i   # 300 x 2s = 10 min (VMs lentas tardan en estabilizar Flannel)
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
    kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=240s

    wait_for_node_ready

    # NODO UNICO: quitamos el taint de control-plane para poder programar cargas.
    print_subheader "Quitando taint de control-plane (nodo único)"
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

    print_subheader "Aplicando Multus CNI (Thick Mode)"
    apply_manifest_with_retries "${MULTUS_MANIFEST_URL}" "Multus" 20 5
    wait_for_daemonset "kube-system" "kube-multus-ds" 180
    kubectl rollout status daemonset/kube-multus-ds -n kube-system --timeout=240s || true

    print_subheader "Instalando Cluster Network Addons Operator (ovs-cni)"
    apply_manifest_with_retries "${CNAO_NAMESPACE_URL}" "CNAO namespace" 20 5
    apply_manifest_with_retries "${CNAO_CRD_URL}"       "CNAO CRD"       20 5
    apply_manifest_with_retries "${CNAO_OPERATOR_URL}"  "CNAO operator"  20 5

    rm -f "${flannel_manifest}"

    apply_iptables_rules
    print_success "Red base del clúster desplegada"
}

setup_storage() {
    print_header "CONFIGURANDO STORAGE PERSISTENTE — OpenEBS (FASE 6/6)"

    if ! command -v helm >/dev/null 2>&1; then
        print_subheader "Instalando Helm 3"
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    print_subheader "Instalando OpenEBS (provisioner hostpath)"
    helm repo add openebs https://openebs.github.io/charts >/dev/null 2>&1 || true
    helm repo update >/dev/null
    helm upgrade --install openebs --namespace openebs openebs/openebs --create-namespace

    print_subheader "Esperando a que aparezca la StorageClass openebs-hostpath"
    local i found=""
    for i in $(seq 1 60); do
        if kubectl get storageclass openebs-hostpath >/dev/null 2>&1; then
            found="yes"
            break
        fi
        sleep 2
    done
    [[ -n "${found}" ]] || { print_error "No apareció openebs-hostpath a tiempo"; exit 1; }

    print_subheader "Esperando a que el provisioner de OpenEBS esté Running"
    kubectl rollout status deployment -n openebs -l app=openebs --timeout=180s 2>/dev/null || true

    print_subheader "Marcando openebs-hostpath como StorageClass por defecto"
    # Quitamos el flag default de cualquier otra SC para evitar dos defaults
    for sc in $(kubectl get storageclass -o name); do
        kubectl annotate "${sc}" storageclass.kubernetes.io/is-default-class- >/dev/null 2>&1 || true
    done
    kubectl patch storageclass openebs-hostpath \
        -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

    print_success "openebs-hostpath marcado como default"
}

post_checks() {
    print_header "VALIDACIONES FINALES"

    print_subheader "Nodos"
    kubectl get nodes -o wide

    print_subheader "Pods del sistema"
    kubectl get pods -A

    print_subheader "StorageClass"
    kubectl get storageclass

    print_subheader "Plugins CNI instalados"
    ls -1 /opt/cni/bin

    print_success "Master instalado correctamente (nodo único VirtualBox)"
    print_info "Este nodo es control-plane y worker a la vez."
    print_info "Siguiente paso (desde open5gs-uerasim-fiee/): ./install-open5gs.sh"
    print_info "Los YAML ya están corregidos para nodo único (sin nodeSelector ni taint)."
}

main() {
    check_root
    validate_prereqs
    validate_master_network
    validate_kubeadm_config

    print_header "DESPLIEGUE INICIADO - K8S-FIEE (VirtualBox single-node)"

    prepare_node
    install_components
    setup_ovs_infrastructure
    init_cluster
    setup_networking
    setup_storage
    post_checks
}

main "$@"
