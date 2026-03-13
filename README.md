<div align="center">
<img src="https://img.shields.io/badge/5G-Stand_Alone-00C7B7?style=for-the-badge&logoColor=white"/>
<img src="https://img.shields.io/badge/Kubernetes-v1.28-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white"/>
<img src="https://img.shields.io/badge/Open5GS-3GPP_SA-FF6B35?style=for-the-badge&logoColor=white"/>
<img src="https://img.shields.io/badge/UERANSIM-gNB_+_UE-4CAF50?style=for-the-badge&logoColor=white"/>
<img src="https://img.shields.io/badge/Ubuntu-22.04_LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white"/>
<img src="https://img.shields.io/badge/Tailscale-Zero_Trust-5433FF?style=for-the-badge&logo=tailscale&logoColor=white"/>
<img src="https://img.shields.io/badge/Prometheus-Grafana-F46800?style=for-the-badge&logo=prometheus&logoColor=white"/>

🛰️ 5G SA Network Lab — Open5GS + UERANSIM on Kubernetes
A complete, portable 5G Stand Alone Core running on a single Lenovo T490s laptop
Academic thesis project — FIEE, Universidad Nacional del Callao (UNAC), Peru — 2026
"Virtual 5G Stand Alone Laboratory in Kubernetes for Two Subscribers as a Tool for Improving Professional Competencies"
</div>

🧭 What is this project?
This repository contains everything needed to deploy a fully functional 5G Stand Alone (SA) Core Network on a regular laptop using only open-source tools and Kubernetes.
Instead of expensive hardware or cloud infrastructure, this lab runs on a Lenovo ThinkPad T490s — the kind of machine any engineering student might already own. The goal is to give students and engineers hands-on experience with the same concepts used in real-world Telco Cloud environments.

💡 Who is this for?

Telecom engineering students who want real 5G hands-on practice
Engineers preparing for Core Network / Cloud-Native Network roles
Researchers who need a reproducible 5G SA testbed without a data center
Anyone curious about how a 5G Core actually works

🏗️ Architecture Overview
The lab uses a two-node Kubernetes cluster running entirely inside one laptop via KVM virtualization:

┌────────────────────────────────────────────────────────────────┐
│                    Lenovo T490s (Host)                         │
│              Intel i7-8665U  │  16 GB RAM                      │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  MASTER NODE — alvarolap (192.168.122.1)                │  │
│  │                                                         │  │
│  │   [MongoDB Pod]   [WebUI Pod]   [iPerf3 Server]         │  │
│  │   [Prometheus]    [Grafana]     [kube-system pods]      │  │
│  └──────────────────────┬──────────────────────────────────┘  │
│                         │  KVM Bridge (br0 / virbr0)          │
│  ┌──────────────────────▼──────────────────────────────────┐  │
│  │  WORKER NODE — worker1 KVM VM (192.168.122.7)           │  │
│  │                                                         │  │
│  │  ┌─── 5G Core (Open5GS) ──────────────────────────┐    │  │
│  │  │  AMF │ SMF01 │ SMF02 │ UPF01 │ UPF02           │    │  │
│  │  │  NRF │ AUSF  │ UDM   │ UDR   │ PCF │ BSF       │    │  │
│  │  └────────────────────────────────────────────────┘    │  │
│  │                                                         │  │
│  │  ┌─── Radio Access (UERANSIM) ─────────────────────┐   │  │
│  │  │  gNB (nr-gnb)  │  UE1 (nr-ue)  │  UE2 (nr-ue)  │   │  │
│  │  └────────────────────────────────────────────────┘    │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                │
│  Remote Access: ──── Tailscale VPN (WireGuard) ─────────────► │
└────────────────────────────────────────────────────────────────┘

Why two nodes instead of one?
Running Core NFs (AMF, UPF, etc.) on the worker node and management components (MongoDB, WebUI, Prometheus) on the master node isolates the 5G data plane from the control plane — the same architectural principle used in production Telco Cloud deployments.

⚙️ IP Planning
SegmentElement / PodIP AddressInterfaceRoleHost / KVMalvarolap (Master)192.168.122.1/24virbr0iPerf GatewayWorker1 (KVM VM)192.168.122.7/24eth0 / br0Core + RAN nodeK8s (Flannel)Pod internal range10.244.0.0/24cni0 / flannel.1K8s internalWebUI / MongoDB10.244.0.xeth0 (Pod)Admin accessControl PlaneAMF / NRF / UDM10.42.0.xn2br bridgeN2 signalingSMF01 / SMF0210.42.0.1xn4br bridgeSession mgmt N4User PlaneUERANSIM gNB10.43.0.1n3br bridgeGTP tunnel entryUPF01 / UPF0210.43.0.101/102n3br bridgeGTP N3 terminationN6 (Data Net)UPF Gateway10.45.0.1ogstunExit to iPerf




🧰 Tech Stack
ToolVersionPurposeOpen5GSLatest5G SA Core (AMF, SMF, UPF, NRF, AUSF, UDM, PCF, NSSF)UERANSIMLatestgNB + UE emulation (nr-gnb, nr-ue)Kubernetesv1.28Container orchestration (kubeadm)KVM / QEMU-Hypervisor for Worker1 VMFlannel + Multus-CNI networking (pod-to-pod + multi-interface)OpenEBS-Persistent storage for MongoDBMongoDB-Subscriber database (IMSI, K, OPC)Prometheus-Metrics collection (UPF traffic, pod resources)Grafana-Real-time dashboards (throughput, CPU, memory)Tailscale-Secure mesh VPN for remote cluster accessWireGuard-Encrypted transport layer under Tailscaleiperf3-Throughput & latency benchmarkingUbuntu22.04 LTSOS on host and all VMs

📁 Repository Structure
.
├── KVM-fiee/                  # KVM VM automation scripts (VIRSH)
│   └── create_worker1.sh      # Automated worker1 VM deployment
│
├── VM-KVM/                    # VM configuration files
│
├── k8s-fiee/                  # Kubernetes cluster setup
│   ├── install_master.sh      # Master node init (uses KVM bridge IP)
│   ├── install_worker.sh      # Worker node setup
│   └── worker-join-token.sh   # Generates join token for worker1
│
├── open5gs-uerasim-fiee/      # 5G Core + RAN manifests
│   ├── open5gs/               # YAML manifests per NF (AMF, SMF, UPF...)
│   └── ueransim/              # gNB and UE configuration YAMLs
│
├── monitoring/                # Observability stack
│   ├── prometheus/            # Prometheus config & scrape targets
│   └── grafana/               # Dashboard JSONs (UPF traffic, resources)
│
├── iperf3/                    # Performance test scripts
│   └── run_scenarios.sh       # Runs all 6 experimental scenarios
│
└── README.md

🚀 Deployment Guide (Step by Step)
Prerequisites

Laptop with 8+ CPU threads and 16 GB RAM (tested on Lenovo T490s)
Ubuntu 22.04 LTS installed natively (not inside a VM)
KVM/QEMU enabled (kvm-ok should return "KVM acceleration can be used")
Git, curl, bash


Step 1 — Create the Worker1 Virtual Machine
bashcd KVM-fiee/
chmod +x create_worker1.sh
./create_worker1.sh
This script uses VIRSH to create the KVM virtual machine (worker1) with:

4 vCPUs, 6 GB RAM allocated from the host
Ubuntu 22.04 cloud image
Connected to the virbr0 bridge → gets IP 192.168.122.7

Verify:
bashvirsh list --all
# Should show: worker1   running

Step 2 — Deploy Kubernetes Cluster

⚠️ Important: These scripts use the KVM bridge IP (192.168.122.1) as the master node address — not the Wi-Fi IP. This keeps the cluster stable even when the laptop changes Wi-Fi networks.

On the host (master node):
bashcd k8s-fiee/
chmod +x install_master.sh
./install_master.sh
On worker1 (SSH into it first):
bashssh ubuntu@192.168.122.7
cd k8s-fiee/
./install_worker.sh
Join worker1 to the cluster:
bash# On master:
./worker-join-token.sh    # Generates the kubeadm join command

# Copy the output and run it on worker1
Verify cluster is ready:
bashkubectl get nodes
# NAME          STATUS   ROLES           AGE
# alvarolap     Ready    control-plane   Xm
# worker1       Ready    <none>          Xm

Step 3 — Deploy Open5GS (5G Core)
bashcd open5gs-uerasim-fiee/
kubectl apply -f open5gs/
This deploys all 5G Network Functions as separate pods in the open5gs namespace:
bashkubectl get pods -n open5gs
# AMF, SMF01, SMF02, UPF01, UPF02, NRF, AUSF, UDM, UDR, PCF, BSF
# mongodb, webui → should all show Running
Register your subscribers via the WebUI (port-forward to access):
bashkubectl port-forward svc/webui 3000:3000 -n open5gs
# Open browser: http://localhost:3000
# Add subscribers: IMSI, K key, OPC, APN → one for UE1, one for UE2

Step 4 — Deploy UERANSIM (Radio + Subscribers)
bashkubectl apply -f open5gs-uerasim-fiee/ueransim/
UERANSIM runs with hostNetwork: true so it can reach the Core NFs directly through the bridge network.
Verify registration:
bashkubectl logs -n open5gs <ueransim-gnb-pod>
# Look for: "UE1 registered successfully"
# Look for: "PDU Session established"

Step 5 — Deploy Monitoring (Prometheus + Grafana)
bashcd monitoring/
kubectl apply -f prometheus/
kubectl apply -f grafana/
Access Grafana dashboard:
bashkubectl port-forward svc/grafana 3001:3000 -n monitoring
# Open: http://localhost:3001
# Default: admin / admin
The UPF traffic dashboard shows real-time throughput per subscriber scraped directly from Open5GS metrics endpoints.

Step 6 — Remote Access with Tailscale
bash# Install Tailscale on both master and worker1
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Both nodes will receive stable IPs in the 100.64.x.x range
# Access WebUI, Grafana, kubectl from anywhere — securely

Step 7 — Run Performance Tests (iperf3)
The lab includes 6 experimental scenarios tested with iperf3:
ScenarioUEsProtocolDirectionE1 — Baseline1TCPUplinkE2 — Dual UE2TCPUplinkE3 — TCP Up2TCPUplinkE4 — TCP Down2TCPDownlinkE5 — UDP Up2UDPUplinkE6 — UDP Down2UDPDownlink
bashcd iperf3/
./run_scenarios.sh
# Results: throughput (Mbps), RTT (ms), jitter (ms), CPU%, RAM (MiB)

📊 Results Snapshot
All 6 scenarios were executed successfully with 2 simultaneous subscribers. Key findings:

✅ Both UEs completed 5G-AKA authentication and established PDU sessions
✅ End-to-end data connectivity validated through GTP-U tunnels (N3 interface)
✅ Prometheus + Grafana dashboard confirmed throughput coherence with iperf3 measurements
✅ Remote access via Tailscale validated from external networks
✅ Lab remained stable across all scenarios on consumer-grade hardware


🎓 Academic Context
This project was developed as the undergraduate thesis for the Electronic Engineering degree at the Faculty of Electrical and Electronic Engineering (FIEE), Universidad Nacional del Callao (UNAC), Peru.
Thesis title:

"Development of a Virtual 5G Stand Alone Laboratory in Kubernetes for Two Subscribers as a Tool for Improving Professional Competencies at FIEE UNAC, 2026"

Research problem this solves:
In Peru, hands-on 5G training is restricted to mobile operators and equipment manufacturers. Students graduate without ever touching a 5G Core. This lab changes that — giving any student with a capable laptop the ability to configure AMF, register subscribers, run PDU sessions, and monitor network traffic with industry-standard tools.

🔗 Credits & References
This project builds upon the foundational work of:

@Niloysh (Niloy Saha) — Original Open5GS + Kubernetes testbed automator. The YAML structure and multi-UPF slicing configuration was adapted from his repository.
Open5GS Project — 3GPP-compliant open-source 5G Core
UERANSIM — Open-source 5G UE and gNB simulator

Key modifications made in this project:

Adapted Kubernetes scripts to use fixed KVM bridge IPs instead of Wi-Fi IPs (ensures cluster stability across networks)
Added Tailscale integration for secure remote lab access
Integrated iperf3 test automation for all 6 experimental scenarios
Built Prometheus/Grafana dashboards specifically for UPF traffic monitoring
Documented the full deployment as a reproducible academic lab


📄 License
MIT License — feel free to use, fork, and adapt for your own research or courses.
If this helped your project, a ⭐ on the repo is appreciated!

<div align="center">
Built with ☕ and signal processing knowledge at UNAC, Callao, Peru
"The best way to learn 5G is to break it and fix it yourself."
</div>
