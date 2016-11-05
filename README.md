# All in one cluster : set of VM with BeeGFS & SLURM on CentOS 7.2

Deploys on the same set of VM:
   a BeeGFS cluster with metadata and storage nodes
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

## Accessing the cluster

Simply SSH to the master node using the IP address.

```
# ssh azureuser@123.123.123.123
```

You can log into the first metadata node using the admin user and password specified.
