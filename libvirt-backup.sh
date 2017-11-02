#!/bin/bash

DATE=$(date +%Y-%m-%d)
VM_NAME=""

# VM_NAME=$1
if [ ! -e /backup/backup.lock ]; then

        touch /backup/backup.lock

        mv /backup/.LAST /backup/.OLD
        mv /backup/.CURRENT /backup/.LAST
        echo $DATE > /backup/.CURRENT

       	if [ -e /backup/.OLD ]; then
		rm -rfv /backup/*$(cat /backup/.OLD)*
	fi

	for VM_NAME in `cat /etc/libvirt/vm-backup.list`;
	do

		DISKSPEC=""
		tdisk=""
		BLOCKPULL=""
		CUR_VDISKS=""
		CUR_VDISKS_TYPE=""
		NUM_VDISKS=""
		NEW_VDISK=""
		PULLDISK=""
		NUM_PULLDISKS=""

		echo $VM_NAME

		if virsh list | grep $VM_NAME; then
			echo "Machine name exists - proceeding"
		else
			echo "No such machine! Exiting."
		exit 1
		fi
		
		# Get the current list of virtual disks and their types
		CUR_VDISKS=( `virsh domblklist --details ${VM_NAME} | grep file | grep -v cdrom | awk '{print $4}'` )
		CUR_VDISKS_TYPE=( `virsh domblklist --details ${VM_NAME} | grep file | grep -v cdrom | awk '{print $3}'` )

		# Compose a the diskspec command line argument - this consists of:
		# - the current disk address (vda, vdb, etc)
		# - snapshot filename, which is a randomly generated UUID
		# This is repeated for the number of disks listed in virsh domblklist, and the result is appended 
		# to the DISKSPEC variable.
		NUM_VDISKS=${#CUR_VDISKS[@]}
	
		for (( i=0; i<${NUM_VDISKS}; i++ ));
		do
			echo $i
			echo ${CUR_VDISKS[$i]}
			echo ${CUR_VDISKS_TYPE[$i]}
			NEW_VDISK=`uuidgen`
			echo ${NEW_VDISK}
			DISKSPEC=${DISKSPEC}"--diskspec ${CUR_VDISKS_TYPE[$i]},snapshot=external,file=/var/lib/libvirt/images/${NEW_VDISK}.qcow2 "
		done

		# The DISKSPEC variable composed above is used here.
		virsh snapshot-create-as --domain ${VM_NAME} \
			backup-snapshot "backup snapshot" \
			${DISKSPEC} \
			--disk-only \
			--atomic || exit 1

		# The original virtual disk files were quiesced by the snapshot process - they are here added to a list of files
		# to be added to a TAR format archive along with the domain XML file.
		for disk in ${CUR_VDISKS[@]}; do 
			tdisk=$tdisk" "$disk
		done

		echo tar Scvf /backup/${VM_NAME}-$DATE.tar $tdisk /etc/libvirt/qemu/${VM_NAME}.xml
		tar Scvf /backup/${VM_NAME}-$DATE.tar $tdisk /etc/libvirt/qemu/${VM_NAME}.xml
		
		# The list of virtual disks is acquired again here - the new snapshot list has become the newly defined virtual disk.
		# virsh blockpull will then pull the backing file (the original disk image) into the new disk.
		#
		# This whole thing is not elegant, but it fits within libvirt/QEMU's capabilities as released in CentOS / RHEL 7.
		PULLDISK=( `virsh domblklist --details ${VM_NAME} | grep file | grep -v cdrom | awk '{print $4}'` )
		NUM_PULLDISKS=${#PULLDISK[@]}

		for (( i=0; i<${NUM_PULLDISKS}; i++ ));
		do
			echo $i
			echo ${PULLDISK[$i]}
			echo virsh blockpull --domain ${VM_NAME} --path=/var/lib/libvirt/images/${PULLDISK[$i]} --verbose --wait || exit 1
			virsh blockpull --domain ${VM_NAME} --path=${PULLDISK[$i]} --verbose --wait || exit 1
		done
		
		# Remove the now unnecessary old virtual disk file
		rm -fv ${CUR_VDISKS[@]} || exit 1 
		# Remove the backup snapshot defined for this procedure
		virsh snapshot-delete ${VM_NAME} backup-snapshot --metadata || exit 1
		# Redefine the virtual machine so the domain XML in /etc/libvirt/qemu is updated with the new virtual disk filename.
		virsh dumpxml ${VM_NAME} | virsh define /dev/stdin
	done
	rm /backup/backup.lock
else
        echo "Another backup is in progress. Next time."
fi

