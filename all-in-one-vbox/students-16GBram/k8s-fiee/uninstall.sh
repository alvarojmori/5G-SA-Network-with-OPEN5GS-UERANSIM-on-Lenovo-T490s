#!/bin/bash
# Description: Deep Cleanup for k8s-fiee-unac (VirtualBox single-node)
# Author: Alvaro
# ==============================================================================
# NOTA sobre VMs lentas:
#   'kubeadm reset' intenta detener cada pod sandbox de forma elegante vía
#   crictl. En VMs con pocos recursos cada parada expira (DeadlineExceeded,
#   ~10s por pod) y el reset tarda eternamente o falla. Por eso aquí, ANTES de
#   resetear, detenemos kubelet (para que no recree pods) y forzamos el borrado
#   de TODOS los contenedores y sandboxes. Así el reset no tiene nada que parar.
# ==============================================================================

CRI_SOCK="unix:///run/containerd/containerd.sock"

# Función de color
cecho() {
    local RED="\033[1;31m"
    local GREEN="\033[1;32m"
    local YELLOW="\033[1;33m"
    local NC="\033[0m"

    case $1 in
        "RED")    echo -e "${RED}${2}${NC}" ;;
        "GREEN")  echo -e "${GREEN}${2}${NC}" ;;
        "YELLOW") echo -e "${YELLOW}${2}${NC}" ;;
        *)        echo "$2" ;;
    esac
}

run_deep_cleanup() {
    cecho "RED" "--- INICIANDO LIMPIEZA PROFUNDA ---"

    # 1. Detener kubelet PRIMERO para que deje de recrear pods.
    cecho "YELLOW" "Deteniendo kubelet (para que no recree pods)..."
    sudo systemctl stop kubelet 2>/dev/null

    # 2. Forzar el borrado de TODOS los contenedores y sandboxes (sin espera
    #    elegante). Esto es lo que evita el 'DeadlineExceeded' del reset.
    #    Se envuelve en 'timeout' por si crictl también se cuelga.
    if command -v crictl >/dev/null 2>&1; then
        cecho "YELLOW" "Forzando borrado de contenedores y pods (crictl)..."
        sudo timeout 90 crictl --runtime-endpoint "${CRI_SOCK}" rm  -af 2>/dev/null || true
        sudo timeout 90 crictl --runtime-endpoint "${CRI_SOCK}" rmp -af 2>/dev/null || true
    fi

    # 3. Reset de Kubernetes (ahora rápido: no quedan sandboxes que detener).
    if command -v kubeadm >/dev/null 2>&1; then
        cecho "YELLOW" "Ejecutando kubeadm reset..."
        sudo kubeadm reset -f --cri-socket "${CRI_SOCK}" 2>/dev/null || sudo kubeadm reset -f
    fi

    # 4. Detener el resto de servicios de contenedores.
    cecho "YELLOW" "Deteniendo servicios de contenedores..."
    sudo systemctl stop containerd docker 2>/dev/null

    # 5. Matar shims residuales que pudieran quedar colgados.
    sudo pkill -9 -f containerd-shim 2>/dev/null || true

    # 6. Desmontar volúmenes residuales (evita errores al borrar carpetas).
    cecho "YELLOW" "Desmontando volúmenes de pods residuales..."
    mount | grep '/var/lib/kubelet' | awk '{print $3}' | while read -r mp; do
        sudo umount -l "${mp}" 2>/dev/null || true
    done

    # 7. Limpieza de red (Iptables, IPVS y puentes CNI).
    cecho "YELLOW" "Purgando reglas de red y tablas IPVS..."
    sudo iptables -F 2>/dev/null; sudo iptables -t nat -F 2>/dev/null
    sudo iptables -t mangle -F 2>/dev/null; sudo iptables -X 2>/dev/null
    if command -v ipvsadm >/dev/null 2>&1; then
        sudo ipvsadm --clear 2>/dev/null
    fi

    # Eliminar interfaces virtuales creadas por Flannel/Multus/OVS.
    for ifc in cni0 flannel.1 ovs-system n2br n3br n4br; do
        sudo ip link delete "${ifc}" 2>/dev/null || true
    done

    # 8. Purga de paquetes y binarios.
    cecho "RED" "Eliminando paquetes kubeadm, kubectl, kubelet y motores..."
    sudo apt-mark unhold kubeadm kubectl kubelet 2>/dev/null
    sudo apt-get purge -y kubeadm kubectl kubelet kubernetes-cni 'kube*' containerd.io runc 2>/dev/null
    sudo apt-get autoremove -y 2>/dev/null

    # 9. Borrado físico de directorios (limpieza total).
    cecho "YELLOW" "Borrando directorios de configuración y datos..."
    sudo rm -rf /etc/kubernetes
    sudo rm -rf /var/lib/kubelet
    sudo rm -rf /var/lib/etcd
    sudo rm -rf /etc/cni
    sudo rm -rf /opt/cni
    sudo rm -rf /var/lib/cni
    sudo rm -rf /var/run/kubernetes
    sudo rm -rf /etc/containerd
    sudo rm -rf /var/lib/containerd

    # Limpiar configuración del usuario.
    # OJO: el script corre como root (sudo), por lo que $HOME = /root. Borramos
    # tanto el de root como el del usuario que invocó sudo (SUDO_USER), porque
    # si no, queda un ~/.kube/config huérfano apuntando a un API server muerto.
    rm -rf "$HOME/.kube" "$HOME"/.cache/kube*
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        local user_home
        user_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
        if [ -n "${user_home}" ]; then
            rm -rf "${user_home}/.kube" "${user_home}"/.cache/kube*
            cecho "YELLOW" "Tambien se limpio ${user_home}/.kube"
        fi
    fi

    cecho "GREEN" "--- SISTEMA 100% LIMPIO (COMO NUEVO) ---"
}

# Ejecutar como root
if [ "$EUID" -ne 0 ]; then
  cecho "RED" "Por favor, corre este script como ROOT (sudo ./uninstall.sh)"
  exit 1
fi

run_deep_cleanup
