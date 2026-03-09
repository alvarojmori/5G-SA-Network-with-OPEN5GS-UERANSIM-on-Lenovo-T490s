#!/bin/bash
# Author: Alvaro Juscamayta (FIEE-UNAC)
# Description: Configuración VXLAN en MASTER -> Destino Worker1
# ==============================================================================

# IP del Worker1 (Asegúrate que sea la correcta en tu red KVM)
WORKER1_IP="192.168.122.7" 

echo -e "\e[1;34m--- CONFIGURANDO MASTER (alvarolap) -> WORKER1 ($WORKER1_IP) ---\e[0m"

# N2 Tunnel (Control Plane) - Key 100
sudo ovs-vsctl --may-exist add-port n2br vxlan-n2-to-w1 \
  -- set interface vxlan-n2-to-w1 type=vxlan options:remote_ip=$WORKER1_IP options:key=100

# N3 Tunnel (User Plane) - Key 200
sudo ovs-vsctl --may-exist add-port n3br vxlan-n3-to-w1 \
  -- set interface vxlan-n3-to-w1 type=vxlan options:remote_ip=$WORKER1_IP options:key=200

# N4 Tunnel (N4 Interface) - Key 300
sudo ovs-vsctl --may-exist add-port n4br vxlan-n4-to-w1 \
  -- set interface vxlan-n4-to-w1 type=vxlan options:remote_ip=$WORKER1_IP options:key=300

echo -e "\e[1;32m[OK]\e[0m Túneles creados en Master."
sudo ovs-vsctl show
