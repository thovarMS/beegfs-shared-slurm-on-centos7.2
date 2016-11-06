This ARM template is inspired by Christian Smith template:

   BeeGFS tempate: https://github.com/smith1511/hpc/tree/master/beegfs-shared-on-centos7.2  
   Slurm template: https://github.com/smith1511/hpc/tree/master/slurm-on-centos7.1-hpc   
    <i>I do merge the both template.</i>

<b>All in one cluster (BeeGFS & SLURM) on CentOS 7.2</b>


Deploys on the same set of VM:
   BeeGFS cluster with metadata and storage nodes 
   Slurm as Job Scheduler

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FthovarMS%2Fbeegfs-shared-slurm-on-centos7.2%2Fmaster%2Fazuredeploy.json" target="_blank">
   <img alt="Deploy to Azure" src="http://azuredeploy.net/deploybutton.png"/>
</a>

1. Fill in the mandatory parameters.

2. Select an existing resource group or enter the name of a new resource group to create.

3. Select the resource group location.

4. Accept the terms and agreements.

5. Click Create.

<b>Architecture</b>

The VM called storage0 is the BeeGFS metadata server and the slurm master and also export the following NFS shared storage /share/home & /share/data

The VMs called storage[1-n] are BeeGFS storage server + slurm compute nodes

<img src="https://github.com/thovarMS/beegfs-shared-slurm-on-centos7.2/blob/master/Archi.PNG"  align="middle" width="395" height="274"  alt="architecture" border="1"/> <br></br>

Delpoyed in Azure: 

<img src="https://github.com/thovarMS/beegfs-shared-slurm-on-centos7.2/blob/master/Azure%20Archi.PNG"  align="middle" width="395" height="274"  alt="azure_architecture" border="1"/> <br></br>


<b>BeeGFS</b>

The BeeGFS storage is mounted on /share/scratch on every nodes

<b>SLURM</b>

   Each compute node by default has 1 core avalaible for slurm
   
   You should change the slurm.conf file to adapt it to the real number of cpu:<br></br>
      <code>NodeName=storage[1-number_of_nodes] Procs=16</code>
      
   Then restart the slurm daemon:<br></br>
      <code>systemctl restart slurmctld</code>
      
   And put the nodes on ine with scontrol:<br></br>
      <code>scontrol: update NodeName=storager0 State=RESUME</code>
      <code>scontrol: update NodeName=storager1 State=RESUME</code>
      <code>scontrol: exit</code>

   Then control with: <br></br>
   <code>sinfo -N -l</code>

<b>Accessing the cluster</b>

Simply SSH to the master node using the IP address.

```
# ssh [user]@[public_ip_adress]
```

You can log into the first metadata node using the admin user and password specified.

<b>Still to do</b>

<img alt="Work In Progress" src="https://github.com/thovarMS/beegfs-shared-slurm-on-centos7.2/blob/master/workInProgress.png"/>

- check that all package intalled during install_pkgs_slurm fonction in deployazure.sh are mandatory
- let the user chose how many data disk per VM
- use VMSS instead of VM

