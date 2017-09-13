#!/bin/sh

#============================================================================================
# Generate public key
# To configure cluster from the master Openshift needs to access to itself and to the nodes
# with ssh without password. For this a rsa key is generated and added to the authorized keys
# of each host. Then the public key is added to the authorized keys of each host and then 
# private key (id_rsa) is added in ~/.ssh
#============================================================================================

sleepABit(){
	echo "Sleep a bit..."
	sleep 3
}

#============================================================================================
# In charge of testing the connection from an host to another with ssh
#============================================================================================
publishPublicKeyAndAddToKnowHost(){
	FROM=$1
	TO=$2
	
	#$RSA_FORMATED is already defined at this step
	
	echo "------------------------About to populate public key to $TO"
	
	ssh -i .ssh/root.private.pem -l root $TO "echo "$RSA_FORMATED" >> ~/.ssh/authorized_keys"
	
	echo "------------------------About to add know host $TO in $FROM"
	
	ssh -i .ssh/root.private.pem -l root $FROM "ssh-keyscan -H $TO >> ~/.ssh/known_hosts"
	
	echo "------------------------About to test connection from $FROM to $TO"
	
	TEST_CONNECTION=$(ssh -i .ssh/root.private.pem -l root $FROM "ssh root@$TO \"echo Hello World\"" | grep "Hello World")
	
	if [ -z "$TEST_CONNECTION" ]
	then
			echo "/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ $FROM is not able to ssh to $TO /!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ " 
			exit 1
	else
			echo "\o/\o/\o/\o/\o/\o/\o/\o/\o/\o/ $FROM is able to ssh to $TO \o/\o/\o/\o/\o/\o/\o/\o/\o/\o/"
	fi
}

#============================================================================================
# In charge of generating the key pair and pushing private key to master installer
#============================================================================================
generateKey(){

	echo "------------------------Generate key pair" 
	MASTER_INSTALLER=$1
	
	mkdir tmp
	ssh-keygen -f tmp/id_rsa -N ""
	RSA=$(less tmp/id_rsa.pub)

	saveIFS=$IFS
	IFS=" "
	var2=($RSA)
	IFS=$saveIFS
	RSA_PART_1=${var2[0]}
	RSA_PART_2=${var2[1]}

	# store global variable RSA_FORMATED for publication
	RSA_FORMATED="$RSA_PART_1 $RSA_PART_2"

	cd transfer
	sleepABit
	echo "------------------------------------About to save private key to $MASTER_INSTALLER"
	../tools/psftp.exe -i ../.ssh/root.private.ppk -l root $MASTER_INSTALLER -b transfer-key.txt
	cd ..
	
	# set rights to id_rsa and add it to user agent
	sleepABit
	echo "------------------------------------Change right to 600 on id_rsa"
	ssh -i .ssh/root.private.pem -l root $MASTER_INSTALLER "chmod 600 ~/.ssh/id_rsa"
	sleepABit
	echo "------------------------------------Add key to ssh agent"
	ssh -i .ssh/root.private.pem -l root $MASTER_INSTALLER "eval \$(ssh-agent -s) && ssh-add ~/.ssh/id_rsa"
	
	# this line can be commented to keep the keypair locally
	rm -rf tmp
}

#============================================================================================
# Publish the keys to allow Openshift to configure itself
#============================================================================================
publishKeys(){

	echo "------------Publish keys" 
	
	MASTER_INSTALLER=$1
	OTHER_HOSTS=$2
	
	# first generate the key and publish it on master (installer)
	generateKey $MASTER_INSTALLER
	
	# publish the public key into master and add master to know host on master
	echo "RSA FORMATED IS: $RSA_FORMATED" 
	publishPublicKeyAndAddToKnowHost $MASTER_INSTALLER $MASTER_INSTALLER
	
	# for each nodes publish the public key
	for i in "${!OTHER_HOSTS[@]}"
	do
		# publish the public key into node and add node to know host on master
		publishPublicKeyAndAddToKnowHost $MASTER_INSTALLER ${OTHER_HOSTS[i]}
	done
	
	echo "------------Key publication finished"
}

#============================================================================================
# Run configure host on master etcds and nodes. This step will:
# - Install all the required packaged (ie: git, net-tools, iptables-service etc) 
# - Install Docker
# - Configure docker for production use (use of thinpool)
# -----> cf: https://docs.docker.com/engine/userguide/storagedriver/device-mapper-driver/#configure-direct-lvm-mode-for-production
# -----> Please read the readme to know the necessary steps to add thin-pool
# - deactivate firewalld (as Openshift will configure automatically the iptables)
# - Configure SELinux
# - Install ansible and Openshift ansible if it is the master installer
#============================================================================================
configureHosts(){

	echo "------------Configure host" 
	MASTER_INSTALLER=$1
	OTHER_HOSTS=$2
	
	# launch configuration on master installer
	sleepABit
	sh ./scripts/configure-host.sh $MASTER_INSTALLER "yes"
	
	# for hosts lauch configuration
	for i in "${!OTHER_HOSTS[@]}"
	do
		sleepABit
		sh ./scripts/configure-host.sh ${OTHER_HOSTS[i]} "no"
	done
	
	echo "------------Configuration finished"
}

#============================================================================================
# Perform sanity check on the existence of Master and nodes
#============================================================================================
checkInstallerAndOtherHosts(){
	echo "INSTALLER_HOST=$1"
	echo "OTHER_HOSTS=$2"
	
	if [ -z "$1" ]
	then
			echo "/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ Installer host is missing /!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ " 
			exit 1
	fi
	if [ -z "$2" ]
	then
			echo "/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ Other hosts are missing /!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ " 
			exit 1
	fi
}

#============================================================================================
# In charge of installing openshift
#============================================================================================
installOpenshift(){
	INSTALLER_HOST=$1
	echo "------------Start openshift installation" 
	
	sleepABit
	echo "------------------------Create tmp directory" 
	ssh -i .ssh/root.private.pem -l root $INSTALLER_HOST "mkdir tmp"
	
	sleepABit
	cd transfer
	echo "------------------------About to save hosts file for ansible in server"
	../tools/psftp.exe -i ../.ssh/root.private.ppk -l root $INSTALLER_HOST -b transfer-ansible.txt
	cd ..
	
	sleepABit
	echo "------------------------Move hosts file for ansible to /etc/ansible/" 
	ssh -i .ssh/root.private.pem -l root $INSTALLER_HOST "mv tmp/hosts /etc/ansible/hosts"
	
	sleepABit
	echo "------------------------Remove tmp directory" 
	ssh -i .ssh/root.private.pem -l root $1 "rm -rf tmp"
	
	sleepABit
	echo "------------------------Run playbook" 
	#ssh -i .ssh/root.private.pem -l root $1 "cd openshift-ansible && ansible-playbook playbooks/byo/config.yml"
	
	echo "------------Openshift installation finished" 
}

#============================================================================================
# Start configuration of the cluster
#============================================================================================
startConfiguration(){
	echo "Start configuration" 
	
	file="./cluster.properties"

	if [ -f "$file" ]
	then
	  echo "$file found. So can start cluster configuration"
	  INSTALLER_HOST=$(less $file | grep "INSTALLER" | cut -d'=' -f2)
	  OTHER_HOSTS_STRING=$(less $file | grep "OTHER_HOSTS" | cut -d'=' -f2)
	  
	  # check that installer and other hosts have been added
	  checkInstallerAndOtherHosts $INSTALLER_HOST $OTHER_HOSTS_STRING
	  
	  # retrieve the nodes
	  OTHER_HOSTS=(${OTHER_HOSTS_STRING//,/ })
      
	  # publish the keys to master and to nodes
	  publishKeys $INSTALLER_HOST $OTHER_HOSTS
	  
	  # configure hosts
	  configureHosts $INSTALLER_HOST $OTHER_HOSTS
	  
	  # install openshift
	  installOpenshift $INSTALLER_HOST
	else
	  echo "/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ $file not found. /!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ "
	  exit 1
	fi
}

echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo
echo "                                     					CLUSTER CONFIGURATION											"
echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo

echo
echo "Welcome to cluster configuration assistant."
echo "It will helps you to configure your cluster for Openshift origin."
echo "Before starting please ensure that you have followed the prerequesites in the README or directly "
echo "on the openshift installation guide"
echo
echo "Here is a little recapitulative:"
echo "1/ Hardware requirement:"
echo "---> https://docs.openshift.org/latest/install_config/install/prerequisites.html#hardware"
echo "2/ Ensure your DNS is well configured (all nodes and master must be reslovable from each others):"
echo "---> https://docs.openshift.org/latest/install_config/install/prerequisites.html#prereq-dns"
echo "3/ Each node and master must be able to discuss together:"
echo "---> https://docs.openshift.org/latest/install_config/install/prerequisites.html#prereq-network-access"
echo "4/ For this installer you must insert in .ssh root.private.pem and root.private.ppk file to access the server in root without password"
echo "5/ You must have filled the cluster.properties file with the host name of master and each nodes"
echo "---> Add in the INSTALLER the host of one master. ex: INSTALLER=master1.example.com"
echo "---> Add in the OTHER_HOSTS the host of other hosts (masters, etcd, nodes etc) separated by a comma."
echo "     ex: OTHER_HOSTS=master2.example.com, master3.example.com,etcd1.example.com,node1.example.com,node2.example.com"
echo
echo "Note 1: This installer take the assumption that you added an external disk on each node and master (sdb)"
echo "Note 2: If you want to use an ssh key with password. You must modify the script accordingly"
echo "Note 3: The installation of openshift will be done with ansible script from one of the master selected in INSTALLER"
echo
echo "Here are the steps currently done by the installer:"
echo "1/ Create an ssh key pair without password and install private key on master and public on both master"
echo "and nodes. This will be used by openshift installer to access to both master and nodes for configuration"
echo "2/ Install the necessary packages on both master, nodes and etcds"
echo "3/ Install Docker and configure it for production use (thin-pool) on both master nodes and etcds"
echo "4/ Configure SELinux according to https://docs.openshift.org/latest/install_config/install/prerequisites.html#prereq-selinux"
echo "5/ Prepare ansible script to run"
echo "6/ Install Openshift with Openshift Ansible"
echo
echo
echo "Let's start!!!"
echo
read -p "Start configuration (y?)" START

if [ "$START" == "y" ]
then
		DATE=`date '+%Y-%m-%d.%H-%M-%S'`
		startConfiguration | tee log"$DATE".log
else
        echo "Stop configuration"
fi