#!/usr/bin/env bash
# ============================================================================
# fix-singlenode-yaml.sh
# Corrige TODOS los manifiestos del repo para un clúster de UN SOLO NODO
# (VirtualBox), sin tener que editar a mano cada archivo.
#
# Hace 3 cosas:
#   1. Quita 'nodeSelector' + 'kubernetes.io/hostname' (pods fijados a nodos
#      que no existen: worker1, alvarolap, nuc1, nuc2...).
#   2. Corrige cniVersion inválido en las NetworkAttachmentDefinition
#      (1.4.0 -> 0.3.1), que rompía Multus/OVS.
#   3. Fija MongoDB a 4.4 (las CPUs de VirtualBox no exponen AVX, requerido
#      por MongoDB 5.0+).
#
# Uso:
#   Coloca este archivo en la raíz del proyecto (junto a open5gs-uerasim-fiee/)
#   o dentro de open5gs-uerasim-fiee/, dale permisos y ejecútalo:
#     chmod +x fix-singlenode-yaml.sh
#     ./fix-singlenode-yaml.sh
#
# NOTA sobre el TAINT de control-plane:
#   El taint NO está en los YAML: es una propiedad del nodo. Para un solo
#   nodo se quita en tiempo de ejecución (una vez):
#     kubectl taint nodes --all node-role.kubernetes.io/control-plane-
#   (el install_master.sh ya lo hace en la Fase 5).
# ============================================================================

set -euo pipefail

# Raíz a procesar: el directorio de este script
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

echo "==> Procesando manifiestos bajo: ${ROOT}"

# ── 1. Quitar nodeSelector / kubernetes.io/hostname ─────────────────────────
# Excluimos */overlays/* porque ahí el hostname vive dentro de un nodeAffinity
# con otro formato (matchExpressions) y se rompería el YAML.
echo "[1/3] Quitando nodeSelector y kubernetes.io/hostname (excepto overlays)..."
find . -name '*.yaml' -not -path '*/overlays/*' \
    -exec sed -i '/^[[:space:]]*nodeSelector:[[:space:]]*$/d; /kubernetes\.io\/hostname/d' {} +

# ── 2. Corregir cniVersion inválido en las NAD ──────────────────────────────
echo "[2/3] Corrigiendo cniVersion 1.4.0 -> 0.3.1 en NetworkAttachmentDefinition..."
find . -name '*.yaml' \
    -exec sed -i 's/"cniVersion": "1.4.0"/"cniVersion": "0.3.1"/g; s/"cniVersion":"1.4.0"/"cniVersion":"0.3.1"/g' {} +

# ── 3. MongoDB 4.4 (sin AVX) ────────────────────────────────────────────────
echo "[3/3] Fijando imagen mongo:5.0 -> mongo:4.4..."
find . -name '*.yaml' -exec sed -i 's#image:[[:space:]]*mongo:5.0#image: mongo:4.4#g' {} +

echo
echo "==> Hecho. Verificación rápida:"
echo "--- Restos de hostname (debe salir vacío, salvo overlays no usados) ---"
grep -rn "kubernetes.io/hostname" --include='*.yaml' . | grep -v '/overlays/' || echo "  (limpio)"
echo "--- cniVersion en las NAD ---"
grep -rn "cniVersion" --include='*.yaml' . | grep -v '/overlays/' || true
echo "--- Imagen de MongoDB ---"
grep -rn "image:.*mongo:" --include='*.yaml' . || true

echo
echo "Listo. Ahora puedes aplicar: ./install-open5gs.sh"
echo "Y si el clúster ya está creado, recuerda el taint (una sola vez):"
echo "  kubectl taint nodes --all node-role.kubernetes.io/control-plane-"
