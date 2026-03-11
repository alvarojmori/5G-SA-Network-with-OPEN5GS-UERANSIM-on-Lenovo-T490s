#!/usr/bin/env bash
set -euo pipefail

# =================================================================
# Create libvirt default network + worker1 VM for K8S-fiee cluster
# Result:
#   host virbr0  -> 192.168.122.1/24
#   worker1      -> 192.168.122.7 (DHCP reservation)
#   Autor: AlvaroJuscamayta
# =================================================================

VM_NAME="${VM_NAME:-worker1}"
VM_MAC="${VM_MAC:-52:54:00:3c:8d:98}"
VM_IP="${VM_IP:-192.168.122.7}"

RAM_MB="${RAM_MB:-6300}"
VCPUS="${VCPUS:-3}"
DISK_SIZE_GB="${DISK_SIZE_GB:-60}"

NETWORK_NAME="${NETWORK_NAME:-default}"
BRIDGE_NAME="${BRIDGE_NAME:-virbr0}"
GATEWAY_IP="${GATEWAY_IP:-192.168.122.1}"
NETMASK="${NETMASK:-255.255.255.0}"
DHCP_START="${DHCP_START:-192.168.122.2}"
DHCP_END="${DHCP_END:-192.168.122.254}"

ISO_DIR="${ISO_DIR:-$HOME/iso}"
ISO_NAME="${ISO_NAME:-ubuntu-24.04.4-live-server-amd64.iso}"
ISO_URL="${ISO_URL:-https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso}"
ISO_PATH="${ISO_DIR}/${ISO_NAME}"

DISK_PATH="${DISK_PATH:-/var/lib/libvirt/images/${VM_NAME}.qcow2}"
OS_VARIANT="${OS_VARIANT:-ubuntu24.04}"
CPU_MODEL="${CPU_MODEL:-Skylake-Client-IBRS}"
MACHINE_TYPE="${MACHINE_TYPE:-q35}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1"
    exit 1
  }
}

ensure_requirements() {
  require_cmd sudo
  require_cmd virsh
  require_cmd virt-install
  require_cmd qemu-img
  require_cmd wget
  require_cmd awk
  require_cmd grep
  require_cmd sed
}

ensure_default_network() {
  if ! virsh net-info "$NETWORK_NAME" >/dev/null 2>&1; then
    cat > "/tmp/${NETWORK_NAME}.xml" <<EOF
<network>
  <name>${NETWORK_NAME}</name>
  <forward mode='nat'/>
  <bridge name='${BRIDGE_NAME}' stp='on' delay='0'/>
  <ip address='${GATEWAY_IP}' netmask='${NETMASK}'>
    <dhcp>
      <range start='${DHCP_START}' end='${DHCP_END}'/>
    </dhcp>
  </ip>
</network>
EOF

    echo "==> Defining libvirt network ${NETWORK_NAME}"
    sudo virsh net-define "/tmp/${NETWORK_NAME}.xml"
  else
    echo "==> Network ${NETWORK_NAME} already exists"
  fi

  local active
  active="$(virsh net-info "$NETWORK_NAME" | awk -F': *' '/Active:/ {print $2}')"
  if [[ "$active" != "yes" ]]; then
    echo "==> Starting network ${NETWORK_NAME}"
    sudo virsh net-start "$NETWORK_NAME"
  fi

  local autostart
  autostart="$(virsh net-info "$NETWORK_NAME" | awk -F': *' '/Autostart:/ {print $2}')"
  if [[ "$autostart" != "yes" ]]; then
    echo "==> Enabling autostart for ${NETWORK_NAME}"
    sudo virsh net-autostart "$NETWORK_NAME"
  fi
}

ensure_dhcp_reservation() {
  if sudo virsh net-dumpxml "$NETWORK_NAME" | grep -q "mac='${VM_MAC}'.*ip='${VM_IP}'"; then
    echo "==> DHCP reservation already exists: ${VM_MAC} -> ${VM_IP}"
  else
    echo "==> Adding DHCP reservation: ${VM_MAC} -> ${VM_IP}"
    sudo virsh net-update "$NETWORK_NAME" add ip-dhcp-host \
      "<host mac='${VM_MAC}' name='${VM_NAME}' ip='${VM_IP}'/>" \
      --live --config
  fi
}

ensure_iso() {
  mkdir -p "$ISO_DIR"

  if [[ -f "$ISO_PATH" ]]; then
    echo "==> ISO already exists: $ISO_PATH"
  else
    echo "==> Downloading Ubuntu ISO"
    wget -O "$ISO_PATH" "$ISO_URL"
  fi
}

ensure_vm_absent() {
  if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    echo "ERROR: VM ${VM_NAME} already exists"
    exit 1
  fi
}

ensure_disk_absent() {
  if [[ -e "$DISK_PATH" ]]; then
    echo "ERROR: Disk already exists: $DISK_PATH"
    exit 1
  fi
}

create_disk() {
  echo "==> Creating qcow2 disk: $DISK_PATH (${DISK_SIZE_GB}G)"
  sudo qemu-img create -f qcow2 "$DISK_PATH" "${DISK_SIZE_GB}G"
}

create_vm() {
  echo "==> Creating VM ${VM_NAME}"
  sudo virt-install \
    --name "$VM_NAME" \
    --memory "$RAM_MB" \
    --vcpus "$VCPUS" \
    --cpu "model=${CPU_MODEL},+vmx" \
    --machine "$MACHINE_TYPE" \
    --osinfo "$OS_VARIANT" \
    --boot cdrom,hd \
    --cdrom "$ISO_PATH" \
    --disk "path=${DISK_PATH},format=qcow2,bus=virtio,discard=unmap" \
    --network "network=${NETWORK_NAME},model=virtio,mac=${VM_MAC}" \
    --graphics vnc,listen=127.0.0.1 \
    --video virtio \
    --sound none \
    --rng /dev/urandom \
    --controller type=usb,model=qemu-xhci \
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
    --console pty,target_type=serial \
    --serial pty \
    --noautoconsole
}

show_result() {
  echo
  echo "================ FINAL STATUS ================"
  echo
  echo "[1] Libvirt networks"
  virsh net-list --all
  echo
  echo "[2] Host bridge"
  ip a show "$BRIDGE_NAME" || true
  echo
  echo "[3] DHCP reservation"
  sudo virsh net-dumpxml "$NETWORK_NAME" | sed -n '/<dhcp>/,/<\/dhcp>/p'
  echo
  echo "[4] VM list"
  virsh list --all
  echo
  echo "[5] VM interface"
  virsh domiflist "$VM_NAME" || true
  echo
  echo "Expected host IP   : ${GATEWAY_IP}/24"
  echo "Expected worker1 IP: ${VM_IP}"
  echo
  echo "Check DHCP leases with:"
  echo "  sudo virsh net-dhcp-leases ${NETWORK_NAME}"
  echo
  echo "Open VM serial console with:"
  echo "  virsh console ${VM_NAME}"
  echo
  echo "See VNC display with:"
  echo "  virsh vncdisplay ${VM_NAME}"
}

main() {
  ensure_requirements
  ensure_default_network
  ensure_dhcp_reservation
  ensure_iso
  ensure_vm_absent
  ensure_disk_absent
  create_disk
  create_vm
  show_result
}

main "$@"
