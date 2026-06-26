#!/bin/bash

#Configuring Open5gs according the fiee-unac topology and N.Saha yaml files


# Define the target namespace
NAMESPACE="open5gs"

echo "--- Starting 5G Core Deployment (Open5GS) ---"

# 1. Create Namespace
if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    echo "[+] Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
else
    echo "[i] Namespace $NAMESPACE already exists."
fi

# 2. Deploy Network Attachments (Multus/OVS)
echo "[+] Configuring 5G Networking (N2, N3, N4 interfaces)..."
kubectl apply -k networks5g -n "$NAMESPACE"

# 3. Deploy Subscriber Database (MongoDB)
echo "[+] Deploying MongoDB StatefulSet..."
kubectl apply -k mongodb -n "$NAMESPACE"

# 4. Deploy Open5GS Web Interface
echo "[+] Deploying Open5GS WebUI..."
kubectl apply -k open5gs-webui -n "$NAMESPACE"

# 5. Deploy Core Metrics
echo "[+] Deploying Open5GS Metrics..."
kubectl apply -k msd/overlays/open5gs-metrics -n "$NAMESPACE"

echo "-----------------------------------------------"
echo "[!] Core components applied. Checking status..."
echo "-----------------------------------------------"

# Wait 5 seconds for the API to register the objects
sleep 5
kubectl get pods -n "$NAMESPACE" -o wide
