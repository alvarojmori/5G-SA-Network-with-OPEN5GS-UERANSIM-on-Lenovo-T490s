#####5G-SA-Network-with-OPEN5GS-UERANSIM-on-Lenovo-T490s#########
#################################################################

-This project was developed for my engineering degree. The thesis title is: “DESARROLLO DE UN LABORATORIO VIRTUAL 5G STAND ALONE EN KUBERNETES PARA DOS ABONADOS COMO HERRAMIENTA PARA LA MEJORA DE COMPETENCIAS PROFESIONALES EN LA FIEE UNAC, 2026.”

-This project is built upon the excellent work of @Niloysh regarding Open5GS deployment in Kubernetes. (niloysh/open5gs-k8s-testbed-automator by Niloy Saha)

******Key Modifications & Features******
1) Multi-Node K8s Cluster: Implementation of a multi-node solution where the host laptop acts as the Control Plane and a KVM-based Virtual Machine serves as Worker1.
2) Isolated Networking: Utilized the KVM br0 bridge network for cluster access, ensuring deployment remains within a local environment without requiring public Internet IPs.
3) UERANSIM & Performance: Integrated UERANSIM using hostNetwork to facilitate accurate iPerf3 throughput testing.
4) Dedicated Testing Server: Deployed an iPerf3 server directly on the control node for performance benchmarking.
5) Private Cloud Validation: Validated remote access to the Lenovo T490s cluster via Tailscale, simulating a secure Private Cloud environment.
6) Observability & Slicing: Leveraged @N.Saha’s YAML configurations to monitor traffic KPIs across multiple UPFs, demonstrating Network Slicing capabilities through a Prometheus-Grafana dashboard.


   
