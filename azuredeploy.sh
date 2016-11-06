#!/bin/bash

set -x
#set -xeuo pipefail

if [[ $(id -u) -ne 0 ]] ; then
    echo "Must be run as root"
    exit 1
fi

if [ $# != 4 ]; then
    echo "Usage: $0 <MetadataNodeCount> <StorageNodePrefix> <StorageNodeCount> <TemplateBaseUrl>"
    exit 1
fi

# Set user args
METADATA_COUNT=$1
STORAGE_HOSTNAME_PREFIX=$2
STORAGE_COUNT=$3
TEMPLATE_BASE_URL="$4"
# Use the first storage server for management server
MGMT_HOSTNAME=${STORAGE_HOSTNAME_PREFIX}0
# Slurm config
# Use the first storage server for slurm master
MASTER_HOSTNAME=$MGMT_HOSTNAME
# Use the other storage server as a slurm node also
WORKER_COUNT=$(($STORAGE_COUNT - 1))
WORKER_HOSTNAME_PREFIX=$STORAGE_HOSTNAME_PREFIX
LAST_WORKER_INDEX=$WORKER_COUNT

# Shares
SHARE_HOME=/share/home
SHARE_DATA=/share/data
SHARE_SCRATCH=/share/scratch
BEEGFS_METADATA=/data/beegfs/meta
BEEGFS_STORAGE=/data/beegfs/storage

# Munged
MUNGE_USER=munge
MUNGE_GROUP=munge
MUNGE_VERSION=0.5.11

# SLURM
SLURM_USER=slurm
SLURM_UID=6006
SLURM_GROUP=slurm
SLURM_GID=6006
SLURM_VERSION=15-08-1-1
SLURM_CONF_DIR=$SHARE_DATA/conf

# User
HPC_USER=beegfs
HPC_UID=7007
HPC_GROUP=hpc
HPC_GID=7007

# ----- BeeGFS
is_mgmtnode()
{
    hostname | grep "$MGMT_HOSTNAME"
    return $?
}

is_metadatanode()
{
    lastMetadataNode=$(($METADATA_COUNT - 1))
    
    for i in $(seq 0 $lastMetadataNode); do
        hostname | grep "${STORAGE_HOSTNAME_PREFIX}${i}"
        if [ $? -eq 0 ]; then
            return 0
        fi
    done
    
    # We're not a metadata node
    return 1
}

is_storagenode()
{
    hostname | grep "$STORAGE_HOSTNAME_PREFIX"
    return $?
}

# ----- SLURM
# Returns 0 if this node is the slurm master node.
#
is_master()
{
    hostname | grep "$MASTER_HOSTNAME"
    return $?
}


# Installs all required packages for BeeGFS
#
install_pkgs_beegfs()
{
    echo "##############################################"
    echo "########## in install_pkgs_beegfs ############"
    echo "##############################################"
   yum -y install epel-release
    yum -y install zlib zlib-devel bzip2 bzip2-devel bzip2-libs openssl openssl-devel openssl-libs gcc gcc-c++ nfs-utils rpcbind mdadm wget python-pip kernel kernel-devel openmpi openmpi-devel automake autoconf
    systemctl stop firewalld
    systemctl disable firewalld
}

# Installs all required packages for YUM & SLURM
#
install_pkgs_slurm()
{
    echo "##############################################"
    echo "########## in install_pkgs_slurm #############"
    echo "##############################################"
    rpm --rebuilddb
    updatedb
    yum clean all
    yum -y install epel-release
    #yum --exclude WALinuxAgent,intel-*,kernel*,*microsoft-*,msft-* -y update

    sed -i.bak -e '28d' /etc/yum.conf
    sed -i '28i#exclude=kernel*' /etc/yum.conf

    yum -y install zlib zlib-devel bzip2 bzip2-devel bzip2-libs openssl openssl-devel openssl-libs \
        nfs-utils rpcbind git libicu libicu-devel make zip unzip mdadm wget gsl bc rpm-build  \
        readline-devel pam-devel libXtst.i686 libXtst.x86_64 make.x86_64 sysstat.x86_64 python-pip automake autoconf \
        binutils.x86_64 compat-libcap1.x86_64 glibc.i686 glibc.x86_64 \
        ksh compat-libstdc++-33 libaio.i686 libaio.x86_64 libaio-devel.i686 libaio-devel.x86_64 \
        libgcc.i686 libgcc.x86_64 libstdc++.i686 libstdc++.x86_64 libstdc++-devel.i686 libstdc++-devel.x86_64 \
        libXi.i686 libXi.x86_64 gcc gcc-c++ gcc.x86_64 gcc-c++.x86_64 glibc-devel.i686 glibc-devel.x86_64 libtool libxml2-devel

    sed -i.bak -e '28d' /etc/yum.conf
    sed -i '28iexclude=kernel*' /etc/yum.conf
}

# Partitions all data disks attached to the VM and creates
# a RAID-0 volume with them.
#
setup_data_disks()
{
    echo "##############################################"
    echo "##########  in setup_data_disks  #############"
    echo "##############################################"
    mountPoint="$1"
    filesystem="$2"
    devices="$3"
    raidDevice="$4"
    createdPartitions=""

    # Loop through and partition disks until not found
    for disk in $devices; do
        fdisk -l /dev/$disk || break
        fdisk /dev/$disk << EOF
n
p
1


t
fd
w
EOF
        createdPartitions="$createdPartitions /dev/${disk}1"
    done
    
    sleep 10

    # Create RAID-0 volume
    if [ -n "$createdPartitions" ]; then
        devices=`echo $createdPartitions | wc -w`
        mdadm --create /dev/$raidDevice --level 0 --raid-devices $devices $createdPartitions
        
        sleep 10
        
        mdadm /dev/$raidDevice

        if [ "$filesystem" == "xfs" ]; then
            mkfs -t $filesystem /dev/$raidDevice
            echo "/dev/$raidDevice $mountPoint $filesystem rw,noatime,attr2,inode64,nobarrier,sunit=1024,swidth=4096,nofail 0 2" >> /etc/fstab
        else
            mkfs.ext4 -i 2048 -I 512 -J size=400 -Odir_index,filetype /dev/$raidDevice
            sleep 5
            tune2fs -o user_xattr /dev/$raidDevice
            echo "/dev/$raidDevice $mountPoint $filesystem noatime,nodiratime,nobarrier,nofail 0 2" >> /etc/fstab
        fi
        
        sleep 10
        
        mount /dev/$raidDevice
    fi
}

setup_disks()
{
    echo "##############################################"
    echo "##########    in setup_disks     #############"
    echo "##############################################"
    mkdir -p $SHARE_HOME
    mkdir -p $SHARE_DATA
    mkdir -p $SHARE_SCRATCH
    
    if is_mgmtnode; then
        echo "$SHARE_HOME    *(rw,async)" >> /etc/exports
        echo "$SHARE_DATA    *(rw,async)" >> /etc/exports
        systemctl enable rpcbind || echo "Already enabled"
        systemctl enable nfs-server || echo "Already enabled"
        systemctl start rpcbind || echo "Already enabled"
        systemctl start nfs-server || echo "Already enabled"
    fi
    
    # Dump the current disk config for debugging
    fdisk -l
    
    # Dump the scsi config
    lsscsi
    
    # Get the root/OS disk so we know which device it uses and can ignore it later
    rootDevice=`mount | grep "on / type" | awk '{print $1}' | sed 's/[0-9]//g'`
    
    # Get the TMP disk so we know which device and can ignore it later
    tmpDevice=`mount | grep "on /mnt/resource type" | awk '{print $1}' | sed 's/[0-9]//g'`

    # Get the metadata and storage disk sizes from fdisk, we ignore the disks above
    metadataDiskSize=`fdisk -l | grep '^Disk /dev/' | grep -v $rootDevice | grep -v $tmpDevice | awk '{print $3}' | sort -n -r | tail -1`
    storageDiskSize=`fdisk -l | grep '^Disk /dev/' | grep -v $rootDevice | grep -v $tmpDevice | awk '{print $3}' | sort -n | tail -1`

    if [ $metadataDiskSize -eq $storageDiskSize ]; then
        # If metadata and storage disks are the same size, we grab 6 for meta, 10 for storage
        metadataDevices="`fdisk -l | grep '^Disk /dev/' | grep $metadataDiskSize | awk '{print $2}' | awk -F: '{print $1}' | sort | head -6 | tr '\n' ' ' | sed 's|/dev/||g'`"
        storageDevices="`fdisk -l | grep '^Disk /dev/' | grep $storageDiskSize | awk '{print $2}' | awk -F: '{print $1}' | sort | tail -10 | tr '\n' ' ' | sed 's|/dev/||g'`"
    else
        # Based on the known disk sizes, grab the meta and storage devices
        metadataDevices="`fdisk -l | grep '^Disk /dev/' | grep $metadataDiskSize | awk '{print $2}' | awk -F: '{print $1}' | sort | tr '\n' ' ' | sed 's|/dev/||g'`"
        storageDevices="`fdisk -l | grep '^Disk /dev/' | grep $storageDiskSize | awk '{print $2}' | awk -F: '{print $1}' | sort | tr '\n' ' ' | sed 's|/dev/||g'`"
    fi

    mkdir -p $BEEGFS_STORAGE
    mkdir -p $BEEGFS_METADATA
    
    setup_data_disks $BEEGFS_STORAGE "xfs" "$storageDevices" "md10"
    setup_data_disks $BEEGFS_METADATA "ext4" "$metadataDevices" "md20"

    if ! is_mgmtnode; then
        echo "$MGMT_HOSTNAME:$SHARE_HOME $SHARE_HOME    nfs4    rw,auto,_netdev 0 0" >> /etc/fstab
        echo "$MGMT_HOSTNAME:$SHARE_DATA $SHARE_DATA    nfs4    rw,auto,_netdev 0 0" >> /etc/fstab
        mount -a
        mount | grep "^$SHARE_HOME"
        mount | grep "^$SHARE_DATA"
    fi

    mount -a
}

install_beegfs()
{
    echo "##############################################"
    echo "##########  in install_beegfs    #############"
    echo "##############################################"
    # Install BeeGFS repo
    wget -O beegfs-rhel7.repo http://www.beegfs.com/release/latest-stable/dists/beegfs-rhel7.repo
    mv beegfs-rhel7.repo /etc/yum.repos.d/beegfs.repo
    rpm --import http://www.beegfs.com/release/latest-stable/gpg/RPM-GPG-KEY-beegfs
    
    # Disable SELinux
    sed -i 's/SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0

    if is_mgmtnode; then
        yum install -y beegfs-mgmtd beegfs-utils
        
        # Install management server and client
        mkdir -p /data/beegfs/mgmtd
        sed -i 's|^storeMgmtdDirectory.*|storeMgmtdDirectory = /data/beegfs/mgmt|g' /etc/beegfs/beegfs-mgmtd.conf
        systemctl daemon-reload
        systemctl enable beegfs-mgmtd.service
    fi
    
    if is_metadatanode; then
        yum install -y beegfs-meta
        sed -i 's|^storeMetaDirectory.*|storeMetaDirectory = '$BEEGFS_METADATA'|g' /etc/beegfs/beegfs-meta.conf
        sed -i 's/^sysMgmtdHost.*/sysMgmtdHost = '$MGMT_HOSTNAME'/g' /etc/beegfs/beegfs-meta.conf
        systemctl daemon-reload
        systemctl enable beegfs-meta.service
        
        # See http://www.beegfs.com/wiki/MetaServerTuning#xattr
        echo deadline > /sys/block/sdX/queue/scheduler
    fi
    
    if is_storagenode; then
        yum install -y beegfs-storage
        sed -i 's|^storeStorageDirectory.*|storeStorageDirectory = '$BEEGFS_STORAGE'|g' /etc/beegfs/beegfs-storage.conf
        sed -i 's/^sysMgmtdHost.*/sysMgmtdHost = '$MGMT_HOSTNAME'/g' /etc/beegfs/beegfs-storage.conf
        systemctl daemon-reload
        systemctl enable beegfs-storage.service
    fi
    
    # setup client
    yum install -y beegfs-client beegfs-helperd beegfs-utils
    sed -i 's/^sysMgmtdHost.*/sysMgmtdHost = '$MGMT_HOSTNAME'/g' /etc/beegfs/beegfs-client.conf
    #sed -i  's/Type=oneshot.*/Type=oneshot\nRestart=always\nRestartSec=5/g' /etc/systemd/system/multi-user.target.wants/beegfs-client.service
    echo "$SHARE_SCRATCH /etc/beegfs/beegfs-client.conf" > /etc/beegfs/beegfs-mounts.conf
    systemctl daemon-reload
    systemctl enable beegfs-helperd.service
    systemctl enable beegfs-client.service
}

# Downloads/builds/installs munged on the node.
# The munge key is generated on the master node and placed
# in the data share.
# Worker nodes copy the existing key from the data share.
#
install_munge()
{
    echo "##############################################"
    echo "##########  in install_munge     #############"
    echo "##############################################"
    groupadd $MUNGE_GROUP

    useradd -M -c "Munge service account" -g munge -s /usr/sbin/nologin munge

    wget https://github.com/dun/munge/archive/munge-${MUNGE_VERSION}.tar.gz

    tar xvfz munge-$MUNGE_VERSION.tar.gz

    cd munge-munge-$MUNGE_VERSION

    mkdir -m 700 /etc/munge
    mkdir -m 711 /var/lib/munge
    mkdir -m 700 /var/log/munge
    mkdir -m 755 /var/run/munge

    ./configure -libdir=/usr/lib64 --prefix=/usr --sysconfdir=/etc --localstatedir=/var && make && make install

    chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /var/run/munge

    if is_master; then
        dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key
    mkdir -p $SLURM_CONF_DIR
        cp /etc/munge/munge.key $SLURM_CONF_DIR
    else
        cp $SLURM_CONF_DIR/munge.key /etc/munge/munge.key
    fi

    chown munge:munge /etc/munge/munge.key
    chmod 0400 /etc/munge/munge.key

    systemctl daemon-reload
    systemctl enable munge.service
    systemctl start munge.service

    cd ..
}

# Installs and configures slurm.conf on the node.
# This is generated on the master node and placed in the data
# share.  All nodes create a sym link to the SLURM conf
# as all SLURM nodes must share a common config file.
#
install_slurm_config()
{
    echo "##############################################"
    echo "########## in install_slurm_config ###########"
    echo "##############################################"
    if is_master; then

        mkdir -p $SLURM_CONF_DIR

        if [ -e "$TEMPLATE_BASE_URL/slurm.template.conf" ]; then
            cp "$TEMPLATE_BASE_URL/slurm.template.conf" .
        else
            wget "$TEMPLATE_BASE_URL/slurm.template.conf"
        fi

        cat slurm.template.conf |
        sed 's/__MASTER__/'"$MASTER_HOSTNAME"'/g' |
                sed 's/__WORKER_HOSTNAME_PREFIX__/'"$WORKER_HOSTNAME_PREFIX"'/g' |
                sed 's/__LAST_WORKER_INDEX__/'"$LAST_WORKER_INDEX"'/g' > $SLURM_CONF_DIR/slurm.conf
    fi

    ln -s $SLURM_CONF_DIR/slurm.conf /etc/slurm/slurm.conf
}

# Downloads, builds and installs SLURM on the node.
# Starts the SLURM control daemon on the master node and
# the agent on worker nodes.
#
install_slurm()
{
    echo "##############################################"
    echo "##########    in install_slurm   #############"
    echo "##############################################"
    groupadd -g $SLURM_GID $SLURM_GROUP

    useradd -M -u $SLURM_UID -c "SLURM service account" -g $SLURM_GROUP -s /usr/sbin/nologin $SLURM_USER

    mkdir -p /etc/slurm /var/spool/slurmd /var/run/slurmd /var/run/slurmctld /var/log/slurmd /var/log/slurmctld

    chown -R slurm:slurm /var/spool/slurmd /var/run/slurmd /var/run/slurmctld /var/log/slurmd /var/log/slurmctld

    wget https://github.com/SchedMD/slurm/archive/slurm-$SLURM_VERSION.tar.gz

    tar xvfz slurm-$SLURM_VERSION.tar.gz

    cd slurm-slurm-$SLURM_VERSION

    ./configure -libdir=/usr/lib64 --prefix=/usr --sysconfdir=/etc/slurm && make && make install

    install_slurm_config

    if is_master; then
        wget $TEMPLATE_BASE_URL/slurmctld.service
        mv slurmctld.service /usr/lib/systemd/system
        systemctl daemon-reload
        systemctl enable slurmctld
        systemctl start slurmctld
    else
        wget $TEMPLATE_BASE_URL/slurmd.service
        mv slurmd.service /usr/lib/systemd/system
        systemctl daemon-reload
        systemctl enable slurmd
        systemctl start slurmd
    fi

    cd ..
}


setup_swap()
{
    echo "##############################################"
    echo "##########      in setup_swap    #############"
    echo "##############################################"
    fallocate -l 5g /mnt/resource/swap
	chmod 600 /mnt/resource/swap
	mkswap /mnt/resource/swap
	swapon /mnt/resource/swap
	echo "/mnt/resource/swap   none  swap  sw  0 0" >> /etc/fstab
}

setup_user()
{
    echo "##############################################"
    echo "##########      in setup_user    #############"
    echo "##############################################"
    # disable selinux
    sed -i 's/enforcing/disabled/g' /etc/selinux/config
    setenforce permissive
    
    groupadd -g $HPC_GID $HPC_GROUP

    # Don't require password for HPC user sudo
    echo "$HPC_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    
    # Disable tty requirement for sudo
    sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

    if is_mgmtnode; then
    
        useradd -c "HPC User" -g $HPC_GROUP -m -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER

        mkdir -p $SHARE_HOME/$HPC_USER/.ssh
        
        # Configure public key auth for the HPC user
        ssh-keygen -t rsa -f $SHARE_HOME/$HPC_USER/.ssh/id_rsa -q -P ""
        cat $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub > $SHARE_HOME/$HPC_USER/.ssh/authorized_keys

        echo "Host *" > $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    StrictHostKeyChecking no" >> $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    UserKnownHostsFile /dev/null" >> $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    PasswordAuthentication no" >> $SHARE_HOME/$HPC_USER/.ssh/config

        # Fix .ssh folder ownership
        chown -R $HPC_USER:$HPC_GROUP $SHARE_HOME/$HPC_USER

        # Fix permissions
        chmod 700 $SHARE_HOME/$HPC_USER/.ssh
        chmod 644 $SHARE_HOME/$HPC_USER/.ssh/config
        chmod 644 $SHARE_HOME/$HPC_USER/.ssh/authorized_keys
        chmod 600 $SHARE_HOME/$HPC_USER/.ssh/id_rsa
        chmod 644 $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub
    else
        useradd -c "HPC User" -g $HPC_GROUP -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER
    fi
    
    chown $HPC_USER:$HPC_GROUP $SHARE_SCRATCH
    chown $HPC_USER:$HPC_GROUP $LOCAL_SCRATCH
}

# Sets all common environment variables and system parameters.
#
setup_env()
{
    echo "##############################################"
    echo "##########      in setup_env    #############"
    echo "##############################################"
    echo "net.ipv4.neigh.default.gc_thresh1=1100" >> /etc/sysctl.conf
    echo "net.ipv4.neigh.default.gc_thresh2=2200" >> /etc/sysctl.conf
    echo "net.ipv4.neigh.default.gc_thresh3=4400" >> /etc/sysctl.conf
}

# Every thing went well.
#
all_ok()
{
	SETUP_MARKER=/var/tmp/configured
	if [ -e "$SETUP_MARKER" ]; then
		echo "We're already configured, exiting..."
		exit 0
	fi
	touch $SETUP_MARKER
}
setup_swap
install_pkgs_beegfs
setup_disks
setup_user
setup_env
install_beegfs
install_pkgs_slurm
install_munge
install_slurm
all_ok
# Create marker file so we know we're configured

shutdown -r +1 &
exit 0
