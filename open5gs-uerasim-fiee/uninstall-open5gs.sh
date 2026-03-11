#!/bin/bash
# Author: Alvaro Juscamayta (FIEE-UNAC)
# Description: Uninstall Open5GS Core and clean up Kubernetes resources
# ==============================================================================

NAMESPACE="open5gs"

echo "--- Starting 5G Core Uninstallation (Open5GS) ---"

# 1. Eliminar Métricas
echo "[-] Removing Open5GS Metrics..."
kubectl delete -k msd/overlays/open5gs-metrics -n "$NAMESPACE" --ignore-not-found

# 2. Eliminar funciones del Core (si las instalaste con kustomize en la carpeta open5gs)
if [ -d "open5gs" ]; then
    echo "[-] Removing Open5GS Core Functions..."
    kubectl delete -k open5gs -n "$NAMESPACE" --ignore-not-found
fi

# 3. Eliminar Web Interface
echo "[-] Removing Open5GS WebUI..."
kubectl delete -k open5gs-webui -n "$NAMESPACE" --ignore-not-found

# 4. Eliminar Base de Datos (MongoDB)
echo "[-] Removing MongoDB StatefulSet..."
kubectl delete -k mongodb -n "$NAMESPACE" --ignore-not-found

# 5. Eliminar Configuraciones de Red (Multus/OVS)
echo "[-] Removing 5G Networking (N2, N3, N4 interfaces)..."
kubectl delete -k networks5g -n "$NAMESPACE" --ignore-not-found


echo "-----------------------------------------------"
echo "[✓] Uninstallation complete."
echo "-----------------------------------------------"

# Verificación de recursos restantes
kubectl get all -n "$NAMESPACE"
