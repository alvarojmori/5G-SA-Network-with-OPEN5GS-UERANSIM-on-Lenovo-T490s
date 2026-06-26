#!/bin/bash

echo "Aplicando manifiestos de UERANSIM gNB..."
kubectl apply -k ueransim/ueransim-gnb/ -n open5gs

echo "Aplicando manifiestos de UERANSIM UE..."
kubectl apply -k ueransim/ueransim-ue/ -n open5gs

echo "Esperando unos segundos..."
sleep 10

echo "Pods UERANSIM de UE y gNB iniciados"
kubectl get pods -n open5gs | grep ueransim
