#!/bin/bash

NAMESPACE="open5gs"

echo "Eliminando manifiestos de UERANSIM UE..."
kubectl delete -k ueransim/ueransim-ue/ -n "$NAMESPACE" --ignore-not-found

echo "Eliminando manifiestos de UERANSIM gNB..."
kubectl delete -k ueransim/ueransim-gnb/ -n "$NAMESPACE" --ignore-not-found

echo "Esperando unos segundos..."
sleep 5

echo "Verificando pods restantes de UERANSIM..."
kubectl get pods -n "$NAMESPACE" | grep ueransim || echo "No quedan pods de UERANSIM en el namespace $NAMESPACE"
