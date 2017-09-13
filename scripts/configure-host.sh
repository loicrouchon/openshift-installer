#!/bin/sh


#===================================================================
# Usage
#===================================================================

usageHost(){
	echo "Please provide an host or an ip"
	exit
}

usageInstaller(){
	echo "Please specify with yes or no if it is related to installer"
	exit
}

#===================================================================
# Upload the script
#===================================================================

uploadScript()
{
	HOST=$1
	
	echo
	echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
	echo "						Transfer started"
	echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
	echo
	
	ssh -i .ssh/root.private.pem -l root $HOST "rm -rf tmp"

	cd transfer
	../tools/psftp.exe -i ../.ssh/root.private.ppk -l root $HOST -b transfer-host-pre-configuration.txt
	cd ..
	
	echo
	echo
	echo "Transfer finished"
}

#===================================================================
# Main
#===================================================================

if [ -z $1 ]
then
	usageHost
fi

if [ -z $2 ]
then
	usageInstaller
fi

echo
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo "                    Pre-configure host $1      												"
echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
echo

uploadScript $1

# execute the script 
ssh -i .ssh/root.private.pem -l root $1 "sh tmp/host-pre-configuration.sh $2"
ssh -i .ssh/root.private.pem -l root $1 "rm -rf tmp"