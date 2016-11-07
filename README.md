This ARM template is inspired by Christian Smith template:

   - BeeGFS tempate: https://github.com/smith1511/hpc/tree/master/beegfs-shared-on-centos7.2  
   - Slurm template: https://github.com/smith1511/hpc/tree/master/slurm-on-centos7.1-hpc   
 *I have merged the both template.*

# All in one cluster (BeeGFS & SLURM) on CentOS 7.2

Deploys on the same set of VM:
   - BeeGFS cluster with metadata and storage nodes 
   - Slurm as Job Scheduler

## Click here to deploy:
<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FthovarMS%2Fbeegfs-shared-slurm-on-centos7.2%2Fmaster%2Fazuredeploy.json" target="_blank">
   <img alt="Deploy to Azure" src="http://azuredeploy.net/deploybutton.png"/>
</a>

## Questions for deployement:
1. Fill in the mandatory parameters.

2. Select an existing resource group or enter the name of a new resource group to create.

3. Select the resource group location.

4. Accept the terms and agreements.

5. Click Create.

## Architecture

### Logical Architecture

![Alt text](https://github.com/thovarMS/beegfs-shared-slurm-on-centos7.2/blob/master/Archi.PNG "architecture")

The VM called storage0 is :
- the BeeGFS metadata server + management host
- the slurm master
- NFS server: export the following shared storage /share/home & /share/data

The VMs called storage[1-n] are:
- BeeGFS storage server
- [Optinnal] some of them may also be BeeGFS metadata server (based on the template parameters)
- Slurm compute nodes

### Deployed in Azure

![Alt text](https://github.com/thovarMS/beegfs-shared-slurm-on-centos7.2/blob/master/Azure%20Archi.PNG "azure_architecture")

## BeeGFS

The BeeGFS storage is mounted on /share/scratch on every nodes

## SLURM

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

## Accessing the cluster

Simply SSH to the master node using the IP address.

```
# ssh [user]@[public_ip_adress]
```

You can log into the first metadata node using the admin user and password specified.

## Still to do

<img src="https://github.com/thovarMS/beegfs-shared-slurm-on-centos7.2/blob/master/workInProgress.png" align="middle" />

- check that all package intalled during install_pkgs_slurm fonction in deployazure.sh are mandatory
- let the user chose how many data disk per VM
- use VMSS instead of VM
- use Ganglia for monitoring


