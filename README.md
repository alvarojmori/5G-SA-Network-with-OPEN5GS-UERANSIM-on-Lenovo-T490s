<img width="1725" height="714" alt="image" src="https://github.com/user-attachments/assets/f7d17a85-0ed0-4d84-a993-2069f4b787e6" />

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

5G Stand Alone (SA) is no longer future tech — in Peru, operators like **Entel, Claro, Telefónica and Bitel** are actively evolving toward a pure 5G SA Core, replacing virtualized EPC hardware from Huawei and ZTE with cloud-native architectures from Nokia and Ericsson.

The problem? **Hands-on 5G training is locked behind expensive hardware** that only operators and vendors can afford. Students graduate having studied 5G only in theory — no Core config, no subscriber setup, no real PDU sessions.

This lab changes that. It deploys a **complete, functional 5G SA Core on a single student laptop** — no data center, no vendor license, no budget. Every concept operators run daily is here: AMF, SMF, UPF, GTP tunnels, 5G-AKA authentication, PDU sessions, and real-time QoS dashboards.

**💡 Who is this for?**

- 📡 Telecom students who want real 5G Core hands-on practice before entering the job market
- ☁️ Engineers preparing for Core Network / Telco Cloud / Kubernetes roles
- 🎓 Professors looking for a portable, reproducible 5G lab for their courses
- 🔬 Researchers who need a 5G SA testbed without a data center

---

## 🏗️ Architecture Overview

The lab uses a **two-node Kubernetes cluster** running entirely inside one laptop via KVM:

```
┌──────────────────────────────────────────────────────────────┐
│                   Lenovo T490s (Host)                        │
│             Intel i7-8665U  ·  16 GB RAM                     │
│                                                              │
│  ┌───────────────────────────────────────────────────────┐   │
│  │  MASTER NODE — alvarolap  (192.168.122.1)             │   │
│  │  [MongoDB] [WebUI] [iPerf3] [Prometheus] [Grafana]    │   │
│  └────────────────────┬──────────────────────────────────┘   │
│                       │  KVM Bridge  br0 / virbr0            │
│  ┌────────────────────▼──────────────────────────────────┐   │
│  │  WORKER NODE — worker1 KVM VM  (192.168.122.7)        │   │
│  │                                                       │   │
│  │  ┌── 5G Core (Open5GS) ────────────────────────────┐  │   │
│  │  │  AMF · SMF01 · SMF02 · UPF01 · UPF02            │  │   │
│  │  │  NRF · AUSF · UDM  · UDR  · PCF · BSF           │  │   │
│  │  └─────────────────────────────────────────────────┘  │   │
│  │  ┌── Radio Access (UERANSIM) ──────────────────────┐  │   │
│  │  │  gNB (nr-gnb) · UE1 (nr-ue) · UE2 (nr-ue)      │  │   │
│  │  └─────────────────────────────────────────────────┘  │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                              │
│  Remote: ────── Tailscale VPN (WireGuard) ─────────────────► │
└──────────────────────────────────────────────────────────────┘
```

> **Why two nodes?** Core NFs on worker1 + management on master = data plane isolated from control plane. Same principle used in production Telco Cloud.

---

## ⚙️ IP Planning

<table>
  <thead>
    <tr>
      <th>Segment</th>
      <th>Element / Pod</th>
      <th>IP Address</th>
      <th>Interface</th>
      <th>Role</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td rowspan="2"><b>Host / KVM</b></td>
      <td>alvarolap (Master)</td>
      <td><code>192.168.122.1/24</code></td>
      <td><code>virbr0</code></td>
      <td>K8s control plane · iPerf gateway</td>
    </tr>
    <tr>
      <td>worker1 (KVM VM)</td>
      <td><code>192.168.122.7/24</code></td>
      <td><code>eth0 / br0</code></td>
      <td>Runs Core NFs + UERANSIM</td>
    </tr>
    <tr>
      <td rowspan="2"><b>K8s — Flannel</b></td>
      <td>Pod internal range</td>
      <td><code>10.244.0.0/16</code></td>
      <td><code>cni0 / flannel.1</code></td>
      <td>Pod-to-pod overlay network</td>
    </tr>
    <tr>
      <td>WebUI / MongoDB</td>
      <td><code>10.244.0.38</code> / <code>.29</code></td>
      <td><code>eth0 (pod)</code></td>
      <td>Admin access / Database</td>
    </tr>
    <tr>
      <td rowspan="2"><b>Control Plane N2</b></td>
      <td>AMF</td>
      <td><code>10.10.2.200</code></td>
      <td><code>n2 (multus)</code></td>
      <td>NGAP signaling entry point</td>
    </tr>
    <tr>
      <td>UERANSIM gNB</td>
      <td><code>10.10.2.231</code></td>
      <td><code>n2 (multus)</code></td>
      <td>SCTP association to AMF</td>
    </tr>
    <tr>
      <td rowspan="2"><b>Control Plane N4</b></td>
      <td>SMF01 / SMF02</td>
      <td><code>10.10.4.101</code> / <code>.102</code></td>
      <td><code>n4 (multus)</code></td>
      <td>PFCP Session Management</td>
    </tr>
    <tr>
      <td>UPF01 / UPF02</td>
      <td><code>10.10.4.1</code> / <code>.2</code></td>
      <td><code>n4 (multus)</code></td>
      <td>PFCP Reporting / Association</td>
    </tr>
    <tr>
      <td rowspan="3"><b>User Plane N3/GTP</b></td>
      <td>UERANSIM gNB</td>
      <td><code>10.10.3.231</code></td>
      <td><code>n3 (multus)</code></td>
      <td>GTP-U RAN side (Source)</td>
    </tr>
    <tr>
      <td>UPF01</td>
      <td><code>10.10.3.1</code></td>
      <td><code>n3 (multus)</code></td>
      <td>GTP-U Core side — Instance 1</td>
    </tr>
    <tr>
      <td>UPF02</td>
      <td><code>10.10.3.2</code></td>
      <td><code>n3 (multus)</code></td>
      <td>GTP-U Core side — Instance 2</td>
    </tr>
    <tr>
      <td><b>N6 Data Network</b></td>
      <td>UPF Gateway</td>
      <td><code>10.41.0.X / 10.42.0.X</code></td>
      <td><code>ogstun</code></td>
      <td>Exit to iPerf3 server</td>
    </tr>
  </tbody>
</table>

> ⚠️ **Key design choice:** Cluster binds to the **fixed KVM bridge IP** `192.168.122.1` — not the Wi-Fi IP. The cluster stays alive even when the laptop changes networks.

---

## 🧰 Tech Stack

<table>
  <thead>
    <tr><th colspan="3">🔵 5G Core &amp; RAN</th></tr>
    <tr><th>Tool</th><th>Version</th><th>Role</th></tr>
  </thead>
  <tbody>
    <tr><td><b>Open5GS</b></td><td>latest</td><td>Full 5G SA Core — AMF, SMF×2, UPF×2, NRF, AUSF, UDM, UDR, PCF, BSF, NSSF</td></tr>
    <tr><td><b>UERANSIM</b></td><td>latest</td><td>gNB (<code>nr-gnb</code>) + 2× UE (<code>nr-ue</code>) — 5G-AKA auth + PDU sessions</td></tr>
    <tr><td><b>MongoDB</b></td><td>6.x</td><td>Subscriber DB — IMSI, K key, OPC, APN, S-NSSAI</td></tr>
  </tbody>
</table>

<table>
  <thead>
    <tr><th colspan="3">🟠 Infrastructure &amp; Orchestration</th></tr>
    <tr><th>Tool</th><th>Version</th><th>Role</th></tr>
  </thead>
  <tbody>
    <tr><td><b>Kubernetes</b></td><td>v1.28</td><td>Container orchestration — <code>kubeadm</code> multi-node</td></tr>
    <tr><td><b>KVM / QEMU</b></td><td>—</td><td>Hypervisor for Worker1 VM — VIRSH scripts included</td></tr>
    <tr><td><b>Flannel</b></td><td>—</td><td>Pod-to-pod CNI overlay</td></tr>
    <tr><td><b>Multus</b></td><td>—</td><td>Multi-interface CNI — separate N2, N3, N4 bridges per pod</td></tr>
    <tr><td><b>OpenEBS</b></td><td>—</td><td>Persistent storage for MongoDB across restarts</td></tr>
    <tr><td><b>Ubuntu</b></td><td>22.04 LTS</td><td>OS on host and all VMs</td></tr>
  </tbody>
</table>

<table>
  <thead>
    <tr><th colspan="3">🟢 Observability &amp; Security</th></tr>
    <tr><th>Tool</th><th>Version</th><th>Role</th></tr>
  </thead>
  <tbody>
    <tr><td><b>Prometheus</b></td><td>—</td><td>Scrapes UPF metrics — bytes TX/RX, GTP tunnels, PDU sessions</td></tr>
    <tr><td><b>Grafana</b></td><td>—</td><td>Real-time dashboards — throughput per UE, CPU%, RAM</td></tr>
    <tr><td><b>Tailscale</b></td><td>—</td><td>Zero-trust mesh VPN — remote access from anywhere</td></tr>
    <tr><td><b>WireGuard</b></td><td>kernel 5.6+</td><td>Encrypted transport (Curve25519 + ChaCha20) under Tailscale</td></tr>
    <tr><td><b>iperf3</b></td><td>—</td><td>TCP/UDP benchmarking — 6 experimental scenarios</td></tr>
  </tbody>
</table>

---

## 📁 Repository Structure

```
.
├── KVM-fiee/               # KVM VM automation (VIRSH scripts)
├── VM-KVM/                 # VM configuration files
├── k8s-fiee/               # Kubernetes cluster setup
│   ├── install_master.sh   # Master node init (fixed KVM bridge IP)
│   ├── install_worker.sh   # Worker node setup
│   └── worker-join-token.sh
├── open5gs-uerasim-fiee/   # 5G Core + RAN YAML manifests
├── monitoring/             # Prometheus + Grafana configs & dashboards
├── iperf3/                 # Performance test scripts (6 scenarios)
└── README.md
```

---

## 🚀 Deployment Guide

### Prerequisites
- **8+ CPU threads · 16 GB RAM** (tested on Lenovo T490s i7-8665U)
- **Ubuntu 22.04 LTS** installed natively
- KVM enabled — run `kvm-ok` to verify
- `git`, `curl`, `bash`

---

### Step 1 — Create Worker1 VM

```bash
cd KVM-fiee/
chmod +x create_worker1.sh && ./create_worker1.sh
virsh list --all   # → worker1   running
```

---

### Step 2 — Deploy Kubernetes

```bash
# On master (host):
cd k8s-fiee/ && ./install_master.sh

# On worker1:
ssh ubuntu@192.168.122.7
./install_worker.sh

# Join worker1 to cluster (run on master):
./worker-join-token.sh   # copy output → run on worker1

# Verify:
kubectl get nodes
# alvarolap   Ready   control-plane
# worker1     Ready   <none>
```

---

### Step 3 — Deploy Open5GS (5G Core)

You can use the automatization script.

```bash
kubectl apply -k open5gs-uerasim-fiee/open5gs/
kubectl get pods -n open5gs   # all pods → Running

# Register subscribers via WebUI:
# → http://localhost:3000  (add UE1 and UE2: IMSI, K, OPC, APN)
```

---

### Step 4 — Deploy UERANSIM (RAN + UEs)

You can use the automatization script.

```bash
kubectl apply -f open5gs-uerasim-fiee/ueransim/
kubectl logs -n open5gs <gnb-pod>
# → "UE registered" + "PDU Session established"
```

---

### Step 5 — Deploy Monitoring

You can use the automatization script.

```bash
kubectl apply -K monitoring/
kubectl port-forward svc/grafana 3001:3000 -n monitoring
# → http://localhost:3001  (admin / admin)
```

<img width="903" height="408" alt="image" src="https://github.com/user-attachments/assets/321fe22c-cc18-4b81-b69a-1ac1d1a06f11" />

---

### Step 6 — Remote Access via Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Both nodes get stable IPs: 100.64.x.x
# Access WebUI, Grafana, kubectl from anywhere
```

<img width="886" height="310" alt="image" src="https://github.com/user-attachments/assets/25f693ca-8296-4c73-b53e-24bd341b6bbe" />

<img width="662" height="271" alt="image" src="https://github.com/user-attachments/assets/6a478bba-1a3a-4ffb-a5a0-b61b67f6ef09" />

---

### Step 7 — Run Performance Tests

| Scenario | UEs | Protocol | Direction |
|----------|:---:|----------|-----------|
| E1 — Baseline | 1 | TCP | Uplink |
| E2 — Dual UE | 2 | TCP | Uplink |
| E3 — TCP Up | 2 | TCP | Uplink |
| E4 — TCP Down | 2 | TCP | Downlink |
| E5 — UDP Up | 2 | UDP | Uplink |
| E6 — UDP Down | 2 | UDP | Downlink |

---

## 📊 Results

- ✅ Both UEs completed 5G-AKA auth and established PDU sessions
- ✅ End-to-end GTP-U tunnels validated on N3 interface
- ✅ Prometheus/Grafana throughput matched iperf3 measurements
- ✅ Tailscale remote access confirmed from external networks
- ✅ Lab stable across all 6 scenarios on consumer-grade hardware

---

## 📈 CPU Variance & Throughput Analysis

The system was benchmarked to analyze the correlation between Iperf traffic and CPU consumption. The results demonstrate a clear stability threshold:

**Stable Operating Zone (5–18 Mbps):** The CPU scales linearly with the traffic. At the 18 Mbps mark, the system maintains a perfect balance, ensuring that the NAS (Non-Access Stratum) signaling between UEs and gNB is never interrupted.

**Variance & Jitter Threshold:** Beyond 18 Mbps, we observe an increase in CPU variance. The processing overhead for GTP-U encapsulation starts to grow exponentially, leading to potential jitter in the User Plane.

**System Saturation (25 Mbps):** The graph confirms a 100% CPU saturation point at 25 Mbps. Reaching this limit risks breaking the synchronization between the gNB and UPF, as the CPU can no longer keep up with packet processing.

## 🛡️ Connectivity Resilience

**NAS & GTP Stability:** By keeping the throughput at a recommended 18 Mbps, we prevent the "breakage" of the control plane. The connection between UE1, UE2, and gNB remains rock-solid, and the tunnel to the UPF stays synchronized.

**Resource Margin:** Operating at this level provides enough overhead to handle sudden traffic spikes without affecting the core network functions (AMFs/SMFs).

<img width="1725" height="714" alt="image" src="https://github.com/user-attachments/assets/3fb970b7-e48c-4520-b17b-ce75ee50317d" />

---

## 🎓 Academic Context

Undergraduate thesis — **Electronic Engineering**, FIEE, Universidad Nacional del Callao (UNAC), Peru.

> In Peru, 5G hands-on training is restricted to operators and vendors. Students graduate without ever configuring a Core NF. This lab gives any student with a capable laptop the ability to deploy AMF, register subscribers, run PDU sessions, and monitor traffic with industry-standard tools.

---

## 🔗 Credits

- **[@Niloysh](https://github.com/niloysh/open5gs-k8s)** — Open5GS K8s testbed automator (base YAML structure adapted here)
- **[Open5GS](https://open5gs.org)** — 3GPP-compliant open-source 5G Core
- **[UERANSIM](https://github.com/aligungr/UERANSIM)** — Open-source 5G UE and gNB simulator

**Key modifications in this project:**
1. K8s scripts use **fixed KVM bridge IPs** — cluster survives Wi-Fi changes
2. **Tailscale** integration for secure remote lab access
3. **iperf3** automation for all 6 experimental scenarios
4. **Prometheus/Grafana** dashboards for UPF traffic monitoring
5. Full deployment documented as a **reproducible academic lab**

---

<div align="center">

**Built with ☕ at UNAC, Callao, Peru**

*"The best way to learn 5G is to break it and fix it yourself."*

⭐ If this helped your project, a star on the repo is appreciated!

</div>
