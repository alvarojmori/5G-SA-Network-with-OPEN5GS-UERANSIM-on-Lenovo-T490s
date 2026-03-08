# Run the following commands in your laptop to access by ssh  to the worker1 without password


ssh-keygen -t rsa -b 4096

ssh-copy-id worker1

# Edit the hosts in your ssh laptop config 

vi ~/.ssh/config

Host worker1

	Hostname 192.168.122.7
	
	user worker1



