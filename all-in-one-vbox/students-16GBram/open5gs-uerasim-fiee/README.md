#####

Please use the deployment scripts to get the pods automatically.


1) Create the namespace open5gs and the pods open5gs with Metrics
    ./install-open5gs.sh*
2) Create the ueransim pods
    ./install-ueransim.sh*

4) Configure the admin account in the data using the below steps:

   sudo apt-get install python3-pip
   sudo pip3 install virtualenv
   virtualenv venv
   source venv/bin/activate
   --> python3 mongo-tools/add-admin-account.py  ,  after that you can access:

   Open the webui by control plane IP :
     http://192.168.122.1:30300
      -Username: admin  /
      -Password: 1423
   
5) Provisioning the UE1 and UE2
6) In case you want delete the open5gs pods and ueransim you can follow the below data :
     uninstall-open5gs.sh*
      uninstall-ueransim.sh*













