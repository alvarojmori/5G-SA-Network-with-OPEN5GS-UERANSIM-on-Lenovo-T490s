#####

Please use the deployment scripts to get the pods automatically.


1) Create the namespace open5gs and the pods open5gs with Metrics
./install-open5gs.sh*
2) Create the ueransim pods
./install-ueransim.sh*
3) Open the webui by control plane IP :
   http://192.168.122.1:30300
4) Provisioning the UE1y UE  

5) In case you want delete the open5gs pods and ueransim you can follow the below data :
uninstall-open5gs.sh*
uninstall-ueransim.sh*












sudo apt-get install python3-pip
sudo pip3 install virtualenv
virtualenv venv
source venv/bin/activate

