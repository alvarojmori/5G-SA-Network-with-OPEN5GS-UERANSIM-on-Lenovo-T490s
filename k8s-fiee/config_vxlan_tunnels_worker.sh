#!/bin/bash
# Author: Alvaro Juscamayta (FIEE-UNAC)
# Description: CORRECCIÓN de nombres de túneles VXLAN en WORKER1
# ==============================================================================

MASTER_IP="192.168.122.1"

echo -e "\e[1;36m--- CORRIGIENDO TÚNELES EN WORKER1 -> MASTER ($MASTER_IP) ---\e[0m"

# 1. Limpiamos el error anterior (borrar el nombre duplicado si existe)
sudo ovs-vsctl del-port n2br vxlan-to-master 2>/dev/null

# 2. Creamos los túneles con NOMBRES ÚNICOS
# N2 Tunnel - Key 100
sudo ovs-vsctl --may-exist add-port n2br vxlan-n2-master \
  -- set interface vxlan-n2-master type=vxlan options:remote_ip=$MASTER_IP options:key=100

# N3 Tunnel - Key 200
sudo ovs-vsctl --may-exist add-port n3br vxlan-n3-master \
  -- set interface vxlan-n3-master type=vxlan options:remote_ip=$MASTER_IP options:key=200

# N4 Tunnel - Key 300
sudo ovs-vsctl --may-exist add-port n4br vxlan-n4-master \
  -- set interface vxlan-n4-master type=vxlan options:remote_ip=$MASTER_IP options:key=300

echo -e "\e[1;32m[OK]\e[0m Túneles corregidos con nombres únicos."
sudo ovs-vsctl show

