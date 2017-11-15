# Openshift installer

## Introduction

This repository contains all the scripts necessary to create an openshift cluster. You must follow the instruction in the installer.

This is Technology preview and do not ensure that it is 100% safe and ready for production but it will help you in creating your first cluster. So the author could not be responsible in case of error or security issues

This is under MIT liscence so you can reuse it and contribute if you want :)

## Prerequesites

### Instance Choice

You need first to follow the préréquesites indicated in the documentation about :
- [The necessary configuration](https://docs.openshift.org/latest/install_config/install/prerequisites.html#install-config-install-prerequisites)
- [Hosts preparation](https://docs.openshift.org/latest/install_config/install/prerequisites.html#install-config-install-prerequisites)

Here is an example with [OVH](https://www.ovh.com/fr/):
- 1 master with 30GB of RAM and 2 vcpu (SP-30) on centos 7
- 1 application node of 8GB RAM and 2 vcpu (VPS SSD 3) on centos 7
- 1 infrastructure node of 8GB RAM and 2 vcpu (VPS SSD 3) on centos 7
- As much additionnal SSDs (50GB is enougth) ass nodes and master.

First you need to create a ssh keypair to connect to your instance.

Here is an example of architecture on OVH:

![architecture](https://github.com/speedfl/openshift-installer/blob/master/images/architecture.png?raw=true)


### Connection root

You then have to create an ssh key pair to connect in root.
You have to save the pem file, the ppk and keep the public key in ```.ssh```
Then connect to your host and be super user with ```sudo -s``` and copy the public key in ```.ssh/authorized_keys```

Example of command (if the directory do not exists):

```
touch ~/.ssh/authorized_keys && echo "ssh-rsa <YOUR_KEY>" >>> ~/.ssh/authorized_keys
```


### Associate nodes and hosts to sub domains
You need to create a subdomain and associate to each nodes:

example:
- master.example.com
- master2.example.com
- node1.example.com

Then you have to modify the DNS entry to point to the correct IPs:

```
example.com.	        0	A	<IP NODE1>
master.example.com.	    0	A	<IP MASTER>
node1.example.com.	    0	A	<IP NODE1>
node2.example.com.	    0	A	<IP NODE2>
```

You can create wildcards like:

```
*.app.example.com.	    0	A	<IP NODE>
```


**Important notice: Ensure that each nodes are reachable from each others**


## Installation des paquets nécessaire


### Additionnal disks

To configure docker for production we need to configure it for thinpool. The installer can configure it but you need first to add the additionnal disks as mention in Prerequesites.

You can have a look to OVH documentation for this:
https://www.ovh.com/fr/g1863.creer_et_configurer_un_disque_supplementaire_sur_une_instance

As stated a 50GB disk is sufficiant

**The installer take the assumption that disk is called sdb. So if the name is not correct you need to modify the script accordingly in ```./script/host-pre-configuration.sh```**


![architecture](https://github.com/speedfl/openshift-installer/blob/master/images/disklist.png?raw=true)


### Launch the installer

You need to fill the file ```cluster.properties``` in this way:

```
INSTALLER=<one of the master host>
OTHER_HOSTS=<other hosts separated by a comma>
```

*exemple:*

```
INSTALLER=master.example.com
OTHER_HOSTS=master2.example.com,etcd1.example.com,node1.example.com,node2.example.com
```

Then the ```./ansible/hosts``` with the desired configuration

**Attention: cluster.properties content must match the hosts one**

<br/>

To finish run the installer with:

```.\scripts\configure-cluster.sh```

<br/>

The scruot is in charge of the configuration of each hosts:
- Generate an ssh key pair to access from master to other hosts to configure them during ansible
- For all hosts:
 - Install necessary packages: git, net-tools, iptables-service etc
 - Install Docker
 - Configre Docker for production (use thinpool for storage)
 - Deactivate firewalld as Openshift will create its own restrictions
 - Configure SELinux
- Deploy your hosts file to the master 
- Launch install of openshift with ansible
