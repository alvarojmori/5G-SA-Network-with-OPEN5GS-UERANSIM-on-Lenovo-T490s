#!/bin/bash
# Description: Deep Cleanup for k8s-fiee-unac
# Author: Alvaro
# ==============================================================================

# Función de color corregida para evitar errores de formato
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
    cecho "RED" "--- INICIANDO LIMPIEZA PROFUNDA (MODO TESIS) ---"

    # 1. Reset de Kubernetes
    if [ -x "$(command -v kubeadm)" ]; then
        cecho "YELLOW" "Ejecutando kubeadm reset..."
        sudo kubeadm reset -f
    fi

    # 2. Detención de servicios
    cecho "YELLOW" "Deteniendo servicios de contenedores..."
    sudo systemctl stop kubelet containerd docker 2>/dev/null

    # 3. Desmontar volúmenes residuales (Evita errores de borrado de carpetas)
    cecho "YELLOW" "Desmontando volúmenes de pods residuales..."
    sudo timeout 10s umount $(mount | grep kubelet | cut -d ' ' -f 3) 2>/dev/null

    # 4. Limpieza de Red (Iptables, IPVS y Puentes CNI)
    cecho "YELLOW" "Purgando reglas de red y tablas IPVS..."
    sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
    if [ -x "$(command -v ipvsadm)" ]; then
        sudo ipvsadm --clear 2>/dev/null
    fi
    
    # Eliminar interfaces virtuales creadas por Flannel/Multus/OVS
    sudo ip link delete cni0 2>/dev/null
    sudo ip link delete flannel.1 2>/dev/null
    sudo ip link delete ovs-system 2>/dev/null

    # 5. Purga de paquetes y binarios
    cecho "RED" "Eliminando paquetes kubeadm, kubectl, kubelet y motores..."
    sudo apt-mark unhold kubeadm kubectl kubelet 2>/dev/null
    sudo apt-get purge -y kubeadm kubectl kubelet kubernetes-cni 'kube*' containerd.io runc 2>/dev/null
    sudo apt-get autoremove -y

    # 6. Borrado físico de directorios (Limpieza de rastro total)
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
    
    # Limpiar configuración del usuario Alvaro
    rm -rf $HOME/.kube
    rm -rf $HOME/.cache/kube*

    cecho "GREEN" "--- SISTEMA 100% LIMPIO (COMO NUEVO) ---"
}

# Ejecutar como root
if [ "$EUID" -ne 0 ]; then 
  cecho "RED" "Por favor, corre este script como ROOT (sudo ./uninstall.sh)"
  exit
fi

run_deep_cleanup
