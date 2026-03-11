# 5G SA Network with Open5GS & UERANSIM on Lenovo T490s

![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-5433FF?style=for-the-badge&logo=tailscale&logoColor=white)
![Open5GS](https://img.shields.io/badge/Open5GS-v2.7.x-blue?style=for-the-badge)
![UERANSIM](https://img.shields.io/badge/UERANSIM-v3.2.x-green?style=for-the-badge)

> **Thesis project** — *"Desarrollo de un Laboratorio Virtual 5G Stand Alone en Kubernetes para dos abonados como herramienta para la mejora de competencias profesionales en la FIEE UNAC, 2026."*

A portable, fully functional 5G SA lab running on a single Lenovo T490s laptop. The setup uses KVM to create a multi-node Kubernetes cluster where the host acts as the Control Plane and a virtual machine becomes Worker1. Built on top of [@Niloysh's open5gs-k8s testbed](https://github.com/niloysh/open5gs-k8s-testbed-automator), with several adaptations to make it work in a local, air-gapped environment without public IPs.

---

## What's different here

Most Open5GS + UERANSIM repos target single-node setups or assume cloud infrastructure. This one solves a specific problem: running a realistic multi-node 5G core on commodity hardware you can carry around.

- **Multi-node K8s on one laptop** — host machine = Control Plane, KVM VM = Worker1, connected over `br0` bridge (no cloud, no public IPs)
- **UERANSIM with `hostNetwork`** — needed for accurate iPerf3 throughput numbers; without this, results are unreliable in KVM-nested environments
- **Two UPFs, two slices** — network slicing demonstrated through separate UPF instances, monitored via Prometheus + Grafana
- **Tailscale overlay** — validated remote access to the cluster from outside the local network, simulating a private cloud scenario
- **iPerf3 server on control node** — dedicated performance endpoint for benchmarking UE throughput end-to-end

---

## Architecture
```
┌─────────────────────────────────────────────────────────┐
│                   Lenovo T490s (Host)                   │
│                                                         │
│  ┌──────────────────────┐    ┌─────────────────────┐   │
│  │  Control Plane Node  │    │    Worker1 Node      │   │
│  │   192.168.122.1      │    │   192.168.122.7      │   │
│  │                      │    │  (KVM Virtual Machine│   │
│  │  - 5G Core (AMF,NRF  │    │                      │   │
│  │    AUSF, UDM, UDR,   │◄──►│  - SMF / UPF x2     │   │
│  │    PCF, NSSF, BSF)   │    │  - UERANSIM gNB      │   │
│  │  - iPerf3 Server     │    │  - UERANSIM UE x2    │   │
│  │  - Prometheus/Grafana│    │                      │   │
│  └──────────────────────┘    └─────────────────────┘   │
│                  │                      │               │
│                  └──────── br0 ─────────┘               │
│                      (KVM L2 Bridge)                    │
└─────────────────────────────────────────────────────────┘
                          │
                      Tailscale
                   (remote access)
```

---

## Repository structure
```
.
├── KVM-fiee/               # KVM VM provisioning scripts and network config
├── VM-KVM/                 # Guest VM setup (Worker1 node)
├── open5gs-uerasim-fiee/   # Open5GS + UERANSIM K8s manifests (adapted from @Niloysh)
├── k8s-fiee/               # Cluster bootstrap scripts (kubeadm, CNI, join tokens)
├── iperf3/                 # iPerf3 server deployment and test scripts
├── monitoring/             # Prometheus + Grafana stack YAMLs and dashboards
└── README.md
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Lenovo T490s (or similar x86-64 laptop) | 16 GB RAM minimum recommended |
| Ubuntu 22.04 LTS on host | Tested on this version |
| KVM/QEMU + libvirt | `apt install qemu-kvm libvirt-daemon-system` |
| kubectl + kubeadm | v1.28+ |
| Helm | v3.x |
| Tailscale | Optional, for remote access validation |

---

## Deployment order

### 1. Host setup & KVM bridge
```bash
cd KVM-fiee/
# Review and adapt IP ranges in the scripts before running
bash 01-host-bridge-setup.sh
bash 02-kvm-vm-create.sh
```

The bridge `br0` is what ties the two K8s nodes together. All cluster traffic goes through it — no `flannel` tunneling over loopback tricks needed.

### 2. Kubernetes cluster
```bash
cd k8s-fiee/
# On host (Control Plane)
bash control-plane-init.sh

# On Worker1 VM — copy and run the join command printed by kubeadm
bash worker-join.sh
```

### 3. Open5GS + UERANSIM
```bash
cd open5gs-uerasim-fiee/
kubectl apply -f namespace.yaml
kubectl apply -f open5gs/
kubectl apply -f ueransim/
```

Check that the gNB registers with the AMF:
```bash
kubectl logs -n open5gs deploy/ueransim-gnb | grep "NG Setup"
```

### 4. Register subscribers

Access the Open5GS WebUI at `http://192.168.122.1:3000` and add two subscribers with their IMSI, Key, and OPc values. The default credentials from the @Niloysh setup apply unless you've changed them.

### 5. iPerf3 test
```bash
cd iperf3/
# Start server (already deployed on control node)
kubectl apply -f iperf3-server.yaml

# Run test from UE tunnel interface inside Worker1
bash run-iperf3-ue1.sh
bash run-iperf3-ue2.sh
```

### 6. Monitoring
```bash
cd monitoring/
kubectl apply -f prometheus/
kubectl apply -f grafana/
# Access Grafana at http://192.168.122.1:32000
```

The dashboard shows per-UPF traffic KPIs. With two UPF instances you can visually verify that UE1 and UE2 are hitting different slices.

---

## Known issues / gotchas

**iPerf3 results look wrong without `hostNetwork`**
UERANSIM pods need `hostNetwork: true` in their spec. Without it, the GTP tunnel traffic goes through an extra NAT layer inside the KVM VM and throughput numbers don't reflect actual UPF performance.

**Bridge disappears after reboot**
The `br0` config in `/etc/netplan/` needs to be set as persistent. Check `KVM-fiee/netplan-br0.yaml` and make sure it's applied with `netplan apply` before starting the cluster.

**kubeadm join token expires in 24h**
If you're setting this up across multiple sessions, regenerate with:
```bash
kubeadm token create --print-join-command
```
**Worker1 IP must be static**
`192.168.122.7` is hardcoded in several K8s node configs. If the VM gets a different DHCP lease, things break. Set a static IP on the VM or configure a DHCP reservation in libvirt.

---

## Results snapshot

| Test | UE1 (Slice 1) | UE2 (Slice 2) |
|---|---|---|
| iPerf3 TCP (30s) | ~X Mbps | ~X Mbps |
| PDU session setup | ✅ | ✅ |
| Grafana UPF metrics | ✅ | ✅ |
| Tailscale remote access | ✅ | — |

*(Fill in with your actual iPerf3 numbers from the thesis)*

---

## Credits

- [@Niloysh](https://github.com/niloysh) — [open5gs-k8s-testbed-automator](https://github.com/niloysh/open5gs-k8s-testbed-automator), the base K8s deployment this work builds on
- [Open5GS](https://open5gs.org/) — 5G core implementation
- [UERANSIM](https://github.com/aligungr/UERANSIM) — UE and gNodeB simulator

---

## License

MIT — feel free to adapt for your own academic or lab work. If you build on this for another thesis or course project, a mention or link back is appreciated but not required.
