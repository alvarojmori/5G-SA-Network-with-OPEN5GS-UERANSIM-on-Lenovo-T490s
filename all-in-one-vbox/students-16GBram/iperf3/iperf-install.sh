#!/bin/bash

# Define the namespace
NAMESPACE="data-network"
YAML_FILE="iperf-server.yaml"

echo "--- Initializing Performance Network ---"

# 1. Create the namespace if it doesn't exist
if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    echo "[+] Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE"
else
    echo "[i] Namespace $NAMESPACE already exists."
fi

# 2. Apply the iPerf3 Server manifest
echo "[+] Deploying iPerf3 Server..."
kubectl apply -f "$YAML_FILE"
