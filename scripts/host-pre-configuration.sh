#!/bin/bash

#======================================================================================================================
# Test docker installation
#======================================================================================================================
testDockerInstall(){
echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "                                                   Testing docker installation									"
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo

EXPECTED_OUTPUT="Hello from Docker!";

TEST_INSTALL=$(docker run hello-world | grep "$EXPECTED_OUTPUT")

echo "EXPECTED_OUPUT IS: $EXPECTED_OUTPUT"
echo "OUPUT IS         : $TEST_INSTALL"

if [ "$TEST_INSTALL" == "$EXPECTED_OUTPUT" ]
then
        echo "Docker was installed successfully"
else
        echo "/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\  Docker installation failed /!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ "
		exit 1
fi
}

#======================================================================================================================
# In case the volume exists (after a first docker installation for example)
# Needs to remove it first
# 1/ remove the volume  the logical volume 
# 2/ remove the volume group docker in case it exists
# 3/ remove the partition
#======================================================================================================================
cleanVolumeDocker(){
echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "                                                           Process cleaning											"
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo

# check if a mapper already exists
TEST_MAPPER=$(ls /dev/mapper/ | grep docker-thinpool)

if [ -z "$TEST_MAPPER" ]
then
        echo "Thin pool mapper does not exist"
else
		echo "Thin pool mapper exists so remove it"
		lvremove -f /dev/mapper/docker-thinpool
		rm /ect/lvm/backup/docker
fi

# check if volume GROUP exists
TEST_VG=$(vgdisplay docker | grep docker)

if [ -z "$TEST_VG" ]
then
        echo "Volume group docker does not exist"
else
		echo "Volume group docker exists so remove it"
		vgremove -f docker
fi

# test if the partition exists
TEST_PARTITION=$(lsblk | grep sdb1)

if [ -z "$TEST_VG" ]
then
        echo "Partition does not exist"
else
		echo "Partition exists so remove it"
		(
		echo d # Remove the partition
		echo w # Write changes
		) | fdisk /dev/sdb
fi
}


# this define if it the host which will perform the installation
IS_INSTALLER=$1

yum clean all
yum makecache fast

#======================================================================================================================
# Install basic packages
#======================================================================================================================
echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "                                     	                   Installing basic packages										"
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo

yum install -y wget \
git \
net-tools \
bind-utils \
iptables-service \
bridge-utils \
yum-utils \
device-mapper-persistent-data \
lvm2

if [ "$IS_INSTALLER" == "yes" ]
then
	echo "Install ansible and openshift-ansible"
	
	yum-config-manager --add-repo https://github.com/CentOS-PaaS-SIG/centos-release-openshift-origin/blob/master/CentOS-OpenShift-Origin.repo?raw=true
	
	yum install -y epel-release \
	http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el7.rf.x86_64.rpm \
	ansible \
	pyOpenSSL \
	python-lxml 
	
	git clone https://github.com/openshift/openshift-ansible.git
	
	cd openshift-ansible
	# take latest tag on 3.6
	git checkout release-3.6
	
	echo "Openshift-ansible version is: $(git describe)"
	echo "ansible version is: $(ansible --version)"
	
	cd ..
else
	echo "Skip ansible install"
fi

#======================================================================================================================
# Removing previous docker installation
#======================================================================================================================
echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "                            		              Removing previous docker installation									"
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo

yum remove -y docker \
docker-common \
docker-selinux \
docker-engine
	
#======================================================================================================================
# Install docker
#======================================================================================================================
echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "                                                       Installing docker											"
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo

yum makecache fast
yum install -y docker \
python-docker-py

# in case of previous installation daemon can be there so delete it
rm /etc/docker/daemon.json
systemctl start docker
testDockerInstall

#======================================================================================================================
# Configure lvm
#======================================================================================================================
echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "                                                   Configure lvm for production								"
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo

# clean docker volume in case it is required
cleanVolumeDocker

systemctl stop docker

lvmconf --disable-cluster

# as docker-storage-setup is not available on community edition it must be done manually
# https://docs.docker.com/engine/userguide/storagedriver/device-mapper-driver/#configure-direct-lvm-mode-for-production

# assuming that disk has been added (cf: README)
# with fdisk command create a new partition which will be called sdb1
(
echo n # Add a new partition
echo p # Primary partition
echo 1 # Partition number
echo   # First sector (Accept default: 1)
echo   # Last sector (Accept default: varies)
echo w # Write changes
) | fdisk /dev/sdb

pvcreate /dev/sdb1

vgcreate docker /dev/sdb1

(
echo y
) | lvcreate --wipesignatures y -n thinpool docker -l 95%VG

lvcreate --wipesignatures y -n thinpoolmeta docker -l 1%VG

lvconvert -y \
--zero n \
-c 512K \
--thinpool docker/thinpool \
--poolmetadata docker/thinpoolmeta

file="/etc/lvm/profile/docker-thinpool.profile"
if [ -f "$file" ]
then
	echo "/etc/lvm/profile/docker-thinpool.profile found just update it"
else 
	echo "/etc/lvm/profile/docker-thinpool.profile not found so create it"
	touch /etc/lvm/profile/docker-thinpool.profile
fi

THINPOOL_PROFILE_CONTENT="activation {
  thin_pool_autoextend_threshold=80
  thin_pool_autoextend_percent=20
}"

echo "$THINPOOL_PROFILE_CONTENT" > /etc/lvm/profile/docker-thinpool.profile

lvchange --metadataprofile docker-thinpool docker/thinpool

lvs -o+seg_monitor

rm -rf /var/lib/docker/*

# Don't mount the volume as it will make docker failed (it must be exclusive)
DOCKER_STORAGE_SETUP='{
    "storage-driver": "devicemapper",
    "storage-opts": [
    "dm.thinpooldev=/dev/mapper/docker-thinpool",
    "dm.use_deferred_removal=true",
    "dm.use_deferred_deletion=true"
    ]
}'

touch daemon.json
echo "$DOCKER_STORAGE_SETUP" > daemon.json
mv daemon.json /etc/docker/daemon.json

systemctl start docker


# first test
TEST_THIN_POOL=$(lvs /dev/docker/thinpool | grep thinpool)

if [ -z "$TEST_THIN_POOL" ]
then
        echo "/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\  lvm configuration failed /!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ "
		exit 1
fi

# second test
TEST_THIN_POOL=$(docker info | grep docker-thinpool)

if [ -z "$TEST_THIN_POOL" ]
then
        echo "/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\  lvm configuration failed /!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ "
		exit 1
fi

# after reinstallation docker images have been removed
testDockerInstall

#======================================================================================================================
# Configure SELinux
#======================================================================================================================
echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "                                                             Configure SELinux											"
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo

TEST_SELINUX=$(less /etc/selinux/config | grep "^SELINUX=")

if [ -z "$TEST_SELINUX" ]
then
	# if it is empty add the configuration
	echo "SELINUX=enforcing" >> /etc/selinux/config
else
	sed -i -e 's/^SELINUX=.*$/SELINUX=enforcing/g' /etc/selinux/config
fi

TEST_SELINUXTYPE=$(less /etc/selinux/config | grep "^SELINUXTYPE=")

if [ -z "$TEST_SELINUXTYPE" ]
then
	# if it is empty add the configuration
	echo "SELINUXTYPE=targeted" >> /etc/selinux/config
else
	sed -i -e 's/^SELINUXTYPE=.*$/SELINUXTYPE=targeted/g' /etc/selinux/config
fi

#======================================================================================================================
# Stop firewalld
#======================================================================================================================
echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "                                     		                    Stop firewalld												"
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo

# deactivate firewalld as openshift will create its own entries in iptables 
systemctl stop firewalld