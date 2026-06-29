#!/bin/bash
# ============================================================================
# install-ueransim-gnb-ue1.sh
# Despliega SOLO el gNB y UN UE (ue1) de UERANSIM.
#
# Pensado para laptops/PC de 16 GB con VirtualBox: en vez de 1 gNB + 2 UE,
# levanta 1 gNB + 1 UE, suficiente para demostrar el registro 5G, el
# establecimiento de la sesión PDU y la conectividad de datos.
#
# ============================================================================
set -euo pipefail

NAMESPACE="open5gs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "--- Despliegue UERANSIM (1 gNB + 1 UE) ---"

# 0. El namespace debe existir (lo crea el despliegue del núcleo)
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo "[ERROR] El namespace ${NAMESPACE} no existe. Despliega primero el núcleo 5G."
    exit 1
fi

# 1. gNB
echo "[+] Desplegando gNB..."
kubectl apply -k ueransim/ueransim-gnb/ -n "${NAMESPACE}"

# 2. UE1 (solo uno) — se aplica la carpeta ue1 directamente, NO el kustomize
#    padre 'ueransim-ue' (que incluiría ue1 + ue2).
echo "[+] Desplegando UE1..."
kubectl apply -k ueransim/ueransim-ue/ue1 -n "${NAMESPACE}"

echo "Esperando unos segundos..."
sleep 10

echo "-----------------------------------------------"
echo "[!] gNB + UE1 aplicados. Estado:"
echo "-----------------------------------------------"
kubectl get pods -n "${NAMESPACE}" | grep -E 'ueransim|gnb|ue1' || true

