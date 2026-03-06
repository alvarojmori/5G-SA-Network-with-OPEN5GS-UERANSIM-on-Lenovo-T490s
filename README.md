# 5G SA Network with Open5GS & UERANSIM on Lenovo T490s

![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-5433FF?style=for-the-badge&logo=tailscale&logoColor=white)



-This project was developed for my engineering degree. The thesis title is: ****“DESARROLLO DE UN LABORATORIO VIRTUAL 5G STAND ALONE EN KUBERNETES PARA DOS ABONADOS COMO HERRAMIENTA PARA LA MEJORA DE COMPETENCIAS PROFESIONALES EN LA FIEE UNAC, 2026.”***

-This project is built upon the excellent work of @Niloysh regarding Open5GS deployment in Kubernetes. (niloysh/open5gs-k8s-testbed-automator by Niloy Saha)

******Key Modifications & Features******
1) Multi-Node K8s Cluster: Implementation of a multi-node solution where the host laptop acts as the Control Plane and a KVM-based Virtual Machine serves as Worker1.
2) Isolated Networking: Utilized the KVM br0 bridge network for cluster access, ensuring deployment remains within a local environment without requiring public Internet IPs.
3) UERANSIM & Performance: Integrated UERANSIM using hostNetwork to facilitate accurate iPerf3 throughput testing.
4) Dedicated Testing Server: Deployed an iPerf3 server directly on the control node for performance benchmarking.
5) Private Cloud Validation: Validated remote access to the Lenovo T490s cluster via Tailscale, simulating a secure Private Cloud environment.
6) Observability & Slicing: Leveraged @N.Saha’s YAML configurations to monitor traffic KPIs across multiple UPFs, demonstrating Network Slicing capabilities through a Prometheus-Grafana dashboard.

***[5G SA Network Topology]<img width="1047" height="646" alt="image" src="https://github.com/user-attachments/assets/5b88f1c2-4e0e-4979-8e0d-49dacb7819aa" />


### Network Breakdown
* **Master Node (192.168.122.1):** Hosted on the Lenovo T490s, managing the 5G Core and the iPerf3 Server.
* **Worker1 Node (192.168.122.7):** A KVM-based VM running the Open5GS functions (SMF, UPF) and UERANSIM (gNB & UEs).
* **Layer 2 Bridge (`br0`):** Provides the networking backbone for internal cluster communication without public IP exposure.
   
