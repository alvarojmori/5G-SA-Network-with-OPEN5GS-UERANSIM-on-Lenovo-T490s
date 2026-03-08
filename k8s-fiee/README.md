1. Control Plane Initialization (Master)

On the physical host (alvarolap), execute the master installation script. This will set up the API Server, Etcd, and the core CNI components (Flannel and Multus).

cd k8s-fiee
chmod +x install_master.sh
sudo ./install_master.sh

2. Computing Node Setup (Worker)
Login by ssh to the worker and clone the alvarojmori repository inside your Virtual Machine and run the worker installer to prepare the container runtime and K8s binaries.


git clone --depth 1 https://github.com/alvarojmori/5G-SA-Network-with-OPEN5GS-UERANSIM-on-Lenovo-T490s.git
cd 5G-SA-Network-with-OPEN5GS-UERANSIM-on-Lenovo-T490s/k8s-fiee

chmod +x install_worker.sh
sudo ./install_worker.sh


3. Cluster Join & Node Labeling

Generate the join command on the Master(alvarolap) and execute it on the Worker.

Note: Ensure you use the bridge IP 192.168.122.1 to allow cross-node communication. Copy and paste in the worker the token that you got by the token script.

Once joined, assign the worker role to the node for better organization and scheduling:


# On Master (alvarolap)
kubectl label node worker1 node-role.kubernetes.io/worker=worker



⚠️ Technical Note: Hardware & Pod Restarts
During the initial deployment, you may observe several restarts in core components like the kube-apiserver or kube-controller-manager.

Reasoning:

-Resource Contention: Since the Master node is a physical laptop running multiple services (KVM, OVS, and the Kubernetes Control Plane), CPU and Memory spikes occur during the initial container orchestration.

-Liveness Probe Timing: Kubernetes health checks might fail temporarily while the system stabilizes under the initial load.

-Stabilization: This behavior is expected in hybrid/laptop-based laboratories. Once the initial handshake is completed, the services reach a Running state and stabilize for 5G traffic testing.

📊 Monitoring & Verification
To validate the cluster health and resource consumption of the 5G Core, deploy the Metrics Server:


cd metrics-kubernetes
kubectl apply -f metrics-server.yaml

# Check resource usage
kubectl top nodes
kubectl top pods -n namespacename
