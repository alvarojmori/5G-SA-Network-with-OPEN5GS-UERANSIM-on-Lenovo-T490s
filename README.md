<div align="center">

<img src="https://img.shields.io/badge/5G-Stand_Alone-00C7B7?style=for-the-badge&logoColor=white"/>
<img src="https://img.shields.io/badge/Kubernetes-v1.28-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white"/>
<img src="https://img.shields.io/badge/Open5GS-3GPP_SA-FF6B35?style=for-the-badge&logoColor=white"/>
<img src="https://img.shields.io/badge/UERANSIM-gNB_%2B_UE-4CAF50?style=for-the-badge&logoColor=white"/>
<img src="https://img.shields.io/badge/Ubuntu-22.04_LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white"/>
<img src="https://img.shields.io/badge/Tailscale-Zero_Trust-5433FF?style=for-the-badge&logo=tailscale&logoColor=white"/>
<img src="https://img.shields.io/badge/Prometheus_%2B_Grafana-Observability-F46800?style=for-the-badge&logo=prometheus&logoColor=white"/>

<br/><br/>

# 🛰️ 5G SA Network Lab
## Open5GS + UERANSIM on Kubernetes

**A complete, portable 5G Stand Alone Core running on a single Lenovo T490s**

*Academic thesis — FIEE, Universidad Nacional del Callao (UNAC), Peru — 2026*

> *"Virtual 5G SA Laboratory in Kubernetes for Two Subscribers as a Tool for Improving Professional Competencies"*

</div>

---

## 🧭 What is this project?

5G Stand Alone (SA) is no longer future tech — in Peru, operators like **Entel, Claro, Telefónica and Bitel** are actively evolving toward a pure 5G SA Core. This lab deploys a **complete, functional 5G SA Core on a single student laptop**.

**💡 Who is this for?**
- 📡 Telecom students seeking real 5G Core hands-on practice.
- ☁️ Engineers preparing for Core Network / Telco Cloud roles.

---

## 🏗️ Architecture Overview

The lab uses a **two-node Kubernetes cluster** running entirely inside one laptop via KVM:

```text
┌──────────────────────────────────────────────────────────────┐
│                    Lenovo T490s (Host)                       │
│              Intel i7-8665U  ·  16 GB RAM                    │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐   │
│  │  MASTER NODE — alvarolap  (192.168.122.1)             │   │
│  │  [MongoDB] [WebUI] [iPerf3] [Prometheus] [Grafana]    │   │
│  └────────────────────┬──────────────────────────────────┘   │
│                        │  KVM Bridge  br0 / virbr0           │
│  ┌────────────────────▼──────────────────────────────────┐   │
│  │  WORKER NODE — worker1 KVM VM  (192.168.122.7)        │   │
│  │                                                       │   │
│  │  ┌── 5G Core (Open5GS) ────────────────────────────┐  │   │
│  │  │  AMF · SMF01 · SMF02 · UPF01 · UPF02             │  │   │
│  │  │  NRF · AUSF · UDM  · UDR  · PCF · BSF            │  │   │
│  │  └─────────────────────────────────────────────────┘  │   │
│  │  ┌── Radio Access (UERANSIM) ──────────────────────┐  │   │
│  │  │  gNB (nr-gnb) · UE1 (nr-ue) · UE2 (nr-ue)       │  │   │
│  │  └─────────────────────────────────────────────────┘  │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  Remote: ────── Tailscale VPN (WireGuard) ─────────────────► │
└──────────────────────────────────────────────────────────────┘
