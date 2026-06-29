#!/usr/bin/env bash
set -euo pipefail

MON_NS="monitoring"
RELEASE="mon"

echo "========================================"
echo " Reset completo de namespace $MON_NS"
echo "========================================"

echo "[1/4] Desinstalando release Helm si existe..."
helm uninstall "$RELEASE" -n "$MON_NS" 2>/dev/null || true

echo "[2/4] Borrando namespace $MON_NS..."
kubectl delete namespace "$MON_NS" --ignore-not-found=true

echo "[3/4] Esperando a que el namespace desaparezca..."
while kubectl get namespace "$MON_NS" >/dev/null 2>&1; do
  echo "Namespace $MON_NS aún existe, esperando..."
  sleep 3
done

echo "[4/4] Recreando namespace $MON_NS..."
kubectl create namespace "$MON_NS"

echo
echo "Namespace recreado correctamente:"
kubectl get namespace "$MON_NS"

echo
echo "Ahora ejecuta:"
echo "./install-dashboard.sh"
