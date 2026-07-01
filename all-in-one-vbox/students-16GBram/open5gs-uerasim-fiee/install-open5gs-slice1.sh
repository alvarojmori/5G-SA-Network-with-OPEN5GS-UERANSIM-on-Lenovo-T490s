#!/bin/bash
# ============================================================================
# # Despliega el nucleo 5G Open5GS COMPLETO pero SIN el slice 2 (sin smf2/upf2).
#
# Para laptops/PC de 16 GB con VirtualBox: reduce la carga en estado estable
# sobre etcd/kube-apiserver (un slice menos), evitando el "flapping" del nodo.
#
# NO modifica ningun YAML del repo: usa los mismos manifiestos que el
# despliegue completo y luego elimina slice2 con su propio kustomize.
#
# Incluye: MongoDB + NRF, SCP, AMF, AUSF, UDM, UDR, BSF, PCF, NSSF + SMF1 + UPF1
#          + WebUI + metricas. (SIN smf2/upf2.)
# ============================================================================
set -euo pipefail

NAMESPACE="open5gs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "--- Despliegue 5G Core (Open5GS) — variante SIN slice2 (16 GB) ---"

# 0. Multus debe haber dejado su CRD
if ! kubectl get crd network-attachment-definitions.k8s.cni.cncf.io >/dev/null 2>&1; then
    echo "[ERROR] No existe el CRD de Multus (NetworkAttachmentDefinition)."
    echo "        Ejecuta primero ../k8s-fiee/install_master_vbox.sh (instala Multus)."
    exit 1
fi

# 1. Namespace
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo "[+] Creando namespace: ${NAMESPACE}"
    kubectl create namespace "${NAMESPACE}"
else
    echo "[i] El namespace ${NAMESPACE} ya existe."
fi

# 2. Redes 5G (Multus/OVS: N2, N3, N4)
echo "[+] Configurando red 5G (interfaces N2, N3, N4)..."
kubectl apply -k networks5g -n "${NAMESPACE}"

# 3. MongoDB
echo "[+] Desplegando MongoDB..."
kubectl apply -k mongodb -n "${NAMESPACE}"

# 4. Nucleo 5G completo (mismas imagenes del overlay de metricas)
echo "[+] Desplegando nucleo 5G (overlay de metricas)..."
kubectl apply -k msd/overlays/open5gs-metrics -n "${NAMESPACE}"

# 5. WebUI
echo "[+] Desplegando WebUI de Open5GS..."
kubectl apply -k open5gs-webui -n "${NAMESPACE}"

# 6. Quitar slice2 (smf2 + upf2) para dejar el nucleo SIN el segundo slice.
#    Se usa el propio kustomize de slice2 -> no se toca ningun YAML.
echo "[+] Eliminando slice2 (smf2 + upf2) para reducir la carga..."
kubectl delete -k open5gs/slices/slice2 -n "${NAMESPACE}" --ignore-not-found
# Respaldo por si algun objeto quedara (borrado por nombre, idempotente):
kubectl delete deployment open5gs-smf2 open5gs-upf2 -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true

# 7. IMPORTANTE: pcf trae un init container 'wait-smf2' que espera a smf2-nsmf:80.
#    Como acabamos de eliminar slice2 (smf2), ese init se quedaria esperando
#    PARA SIEMPRE y bloquearia EN CASCADA a udm -> udr -> nssf -> bsf.
#    Quitamos ese init container del pcf desplegado (no se toca ningun YAML).
echo "[+] Ajustando pcf: quitando dependencia de smf2 (slice2 eliminado)..."
idx=""
for _try in $(seq 1 30); do
    idx=$(kubectl get deployment open5gs-pcf -n "${NAMESPACE}" \
            -o jsonpath='{range .spec.template.spec.initContainers[*]}{.name}{"\n"}{end}' 2>/dev/null \
            | grep -n '^wait-smf2$' | cut -d: -f1)
    [ -n "${idx}" ] && break
    sleep 2
done
if [ -n "${idx}" ]; then
    # jsonpath es 1-based; el patch JSON es 0-based.
    kubectl patch deployment open5gs-pcf -n "${NAMESPACE}" --type=json \
        -p="[{\"op\":\"remove\",\"path\":\"/spec/template/spec/initContainers/$((idx-1))\"}]"
    echo "[i] pcf ahora solo espera a smf1; la cascada se desbloquea."
else
    echo "[i] (pcf no tenia wait-smf2; nada que ajustar)"
fi

echo "-----------------------------------------------"
echo "[!] Componentes aplicados (sin slice2). Estado:"
echo "-----------------------------------------------"
sleep 5
kubectl get pods -n "${NAMESPACE}" -o wide



