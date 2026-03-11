### Install the Iperf3 after the UEs ueransim PODs 

kubectl exec -it -n open5gs $UE1 -- bash -lc 'apt-get update && apt-get install -y iperf3'

kubectl exec -it -n open5gs $UE2 -- bash -lc 'apt-get update && apt-get install -y iperf3'
