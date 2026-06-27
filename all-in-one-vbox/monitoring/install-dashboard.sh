#!/usr/bin/env bash
set -euo pipefail

PROM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MON_NS="monitoring"
RELEASE="mon"
TMP_VALUES="/tmp/mon-values-additional-scrape.yaml"

echo "========================================"
echo " Instalacion Dashboard Prometheus/Grafana"
echo " Modo: additionalScrapeConfigs"
echo "========================================"

echo "[1/9] Verificando herramientas..."
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl no instalado"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "ERROR: helm no instalado"; exit 1; }

echo "[2/9] Verificando archivos existentes..."
for f in \
  "$PROM_DIR/upf-metrics-services.yaml" \
  "$PROM_DIR/additional-scrape-config.yaml" \
  "$PROM_DIR/kustomization.yaml" \
  "$PROM_DIR/mon-values.yaml" \
  "$PROM_DIR/5gcoreservicemonitor.yaml"
do
  [ -f "$f" ] || { echo "ERROR: falta $f"; exit 1; }
done

echo "[3/9] Creando namespace monitoring si no existe..."
kubectl get ns "$MON_NS" >/dev/null 2>&1 || kubectl create namespace "$MON_NS"

echo "[4/9] Eliminando ServiceMonitor viejo si existe..."
# El CRD ServiceMonitor puede no existir aun (se instala con kube-prometheus-stack
# en el paso [8/9]). Ignoramos el error de "resource type not found".
kubectl delete servicemonitor -n "$MON_NS" open5gs-upf-metrics --ignore-not-found 2>/dev/null || true

echo "[5/9] Aplicando Services + Secret (kustomize)..."
kubectl apply -k "$PROM_DIR"

echo "[6/9] Creando values temporal para additionalScrapeConfigs..."
cat > "$TMP_VALUES" <<'EOF'
prometheus:
  prometheusSpec:
    additionalScrapeConfigsSecret:
      enabled: true
      name: open5gs-additional-scrape-configs
      key: open5gs-upf-additional-scrape.yaml
EOF

echo "[7/9] Agregando/actualizando repo Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update

echo "[8/9] Instalando/actualizando kube-prometheus-stack..."
helm upgrade --install "$RELEASE" prometheus-community/kube-prometheus-stack \
  -n "$MON_NS" \
  -f "$PROM_DIR/mon-values.yaml" \
  -f "$TMP_VALUES"

echo "[9/10] Aplicando ServiceMonitor (el CRD ya existe tras instalar el stack)..."
# Esperamos a que el CRD ServiceMonitor este registrado por kube-prometheus-stack
for i in $(seq 1 30); do
  kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 && break
  echo "  ...esperando CRD ServiceMonitor ($i/30)"; sleep 5
done
kubectl apply -f "$PROM_DIR/5gcoreservicemonitor.yaml"

echo "[10/10] Esperando pods de monitoring..."
kubectl wait --for=condition=Ready pod --all -n "$MON_NS" --timeout=300s || true

echo
echo "========================================"
echo " Validaciones"
echo "========================================"
echo

echo "=== Pods monitoring ==="
kubectl get pods -n "$MON_NS"
echo

echo "=== Secret additional scrape ==="
kubectl get secret -n "$MON_NS" open5gs-additional-scrape-configs
echo

echo "=== Services metrics open5gs ==="
kubectl get svc -n open5gs | grep metrics || true
echo

echo "=== Endpoints metrics ==="
kubectl get endpoints -n open5gs open5gs-upf1-metrics open5gs-upf2-metrics || true
echo

echo "=== Pods UPF con labels ==="
kubectl get pods -n open5gs --show-labels | egrep 'upf1|upf2' || true
echo

echo "=== Jobs/targets esperados en Prometheus ==="
echo "Busca el job: open5gs-upf-metrics"
echo

echo "========================================"
echo " Dashboard instalado"
echo "========================================"
echo
echo "Abrir Grafana:"
echo "kubectl -n $MON_NS port-forward svc/${RELEASE}-grafana 3000:80"
echo "URL:  http://localhost:3000"
echo "USER: admin"
echo "PASS: admin12345"
echo
echo "Abrir Prometheus:"
echo "kubectl -n $MON_NS port-forward svc/${RELEASE}-kube-prometheus-stack-prometheus 9090:9090"
echo "URL:  http://localhost:9090/targets"
echo
echo "Consulta de prueba en Prometheus:"
echo 'up{job="open5gs-upf-metrics"}'
