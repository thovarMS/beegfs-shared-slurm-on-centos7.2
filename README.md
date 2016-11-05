# All in one cluster (BeeGFS & SLURM) on CentOS 7.2

This ARM template is inspired by Christian Smith template:

    BeeGFS tempate: https://github.com/smith1511/hpc/tree/master/beegfs-shared-on-centos7.2 
    Slurm template: https://github.com/smith1511/hpc/tree/master/slurm-on-centos7.1-hpc  
    I do merge the both template.

Deploys on the same set of VM:
   BeeGFS cluster with metadata and storage nodes 
   Slurm as Job Scheduler

<img alt="Deploy to Azure" src="https://github.com/thovarMS/beegfs-shared-slurm-on-centos7.2/blob/master/workInProgress.png"/>

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FthovarMS%2Fbeegfs-shared-slurm-on-centos7.2%2Fmaster%2Fazuredeploy.json" target="_blank">
   <img alt="Deploy to Azure" src="http://azuredeploy.net/deploybutton.png"/>
</a>

1. Fill in the mandatory parameters.

2. Select an existing resource group or enter the name of a new resource group to create.

3. Select the resource group location.

4. Accept the terms and agreements.

5. Click Create.

## Architecture:

storage0 : is the BeeGFS metadata server and the slurm master
storage[1-n] : are BeeGFS storage server + slurm compute nodes

storage0 export the following NFS shared storage:
   /share/home & /share/data

The BeeGFS storage is mounted on /share/scratch on every nodes

About SLURM:
   each compute node by default has 1 core avalaible for slurm
   your should change the slurm.conf file to adapt it to the real number of cpu:
      NodeName=storage[1-number_of_nodes] Procs=16
   the restart the slurm daemon:
      systemctl restart slurmctld
   and put the nodes on ine with scontrol:
      scontrol: update NodeName=storager0 State=RESUME
      scontrol: update NodeName=storager1 State=RESUME
      scontrol: exit
   Then control with: sinfo -N -l


## Accessing the cluster

Simply SSH to the master node using the IP address.

```
# ssh [user]@[public_ip_adress]
```

You can log into the first metadata node using the admin user and password specified.
