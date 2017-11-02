# libvirt-backup

A backup script for earlier versions of libvirt included in CentOS / RHEL 7. These versions did not support blockcommit, so in order to backup a QEMU VM one had to pull the base image forward into the differencing disk. Do not use unless you know what you're doing.
