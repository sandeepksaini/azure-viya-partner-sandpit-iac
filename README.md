# Azure Viya CA Env IAC
[Link](https://gitlab.sas.com/ssaima/azure-viya-ca-env-iac)

Full Infrastructure and software deployment orchestration for SAS Viya 4 on Azure K8s.

Use-case: Create a dedicated Azure K8s deployment of SAS Viya 4 for the purposes of a PoX or paid demonstration. Capably sized and deployable in 24 hours.


## Description

The aim of the Azure Viya CA Env IAC is to enable fast deployment of SAS Viya (4) deployed on Azure Kubernetes Service (AKS).
I have utilized the existing automation in these awesome repositories:

https://github.com/sassoftware/viya4-iac-azure

https://github.com/sassoftware/viya4-deployment

As changes are made and improvements/features are added the may or may not seamlessly merge. Work to include new components that require configuration may continue in the future if there is value seen in doing so.

The default config files deploy the the environment with the following configuration:

* Multiple node pools (stateless, stateful, cas, compute, connect)
* Default Internal “Crunchy” PostgreSQL DB
* OpenLDAP for independent management of all users and groups
* NFS Server for application and user (home) data

Variables files allow you to vary the specification of the infrastructure easily (see below)

## Getting Started

### Dependencies
* You must have an Azure subscription to which you (your own Azure login) have authority to create Service Principals with Contributor roles
    * Being the Owner of your own Azure subscription is the target use-case here
    * Go here to request one: https://go.sas.com/cloud
* You must have a Viya 4 order (your own order, that you have created)
    * I won’t go into how you get a SAS software order internally, other to leave some relevant links:
        * https://makeorder.sas.com/makeorder/
        * https://rndconfluence.sas.com/confluence/display/RLSENG/Accessing+internal+container+images+from+external+locations 
* You must have access to your order at https://my.sas.com/en/my-orders.html 
* You must have a Ubuntu machine connected to the SAS corporate network via vpn.sas.com/secure
    * The best way to achieve this is to utilise the latest Windows Subsystem for Linux (WSL2) release of Ubuntu
    * Open the Microsoft Store on your SAS laptop
    * Type ‘Ubuntu 20.04 LTS’ in the search bar
    * Click the blue ‘Get’ button
    * Read the description and follow the steps to enable required the Windows feature
    * You could also (instead) run a Linux VM somewhere with Ubuntu 20.04 on it, it will function exactly the same way other than the requiring network security changes to allow that machine access
* You will need to set aside half a day or so to run the whole setup, by the next day you can have a running environment!

### Deployment

#### Step 1 - Clone
Log into your Ubuntu 20.04 machine and clone this Repo:
```
git clone https://gitlab.sas.com/ssaima/azure-viya-ca-env-iac
```
#### Step 2 - Edit
*core-variables.yaml* MUST be edited with your own details (name email etc)

There are four scripts that each must be run  to complete the process, each with its own folder also containing a variables yaml file.
*resources/deployment_repo-variables.yaml* MUST be edited with your own software order information.
All other variables files contain tested default values. These can be customized to your requirement but changes to client software versions (such as ansible, kubectl or terraform) can cause issues that will need manual troubleshooting and intervention.


#### Step 3 - Run scripts in sequence

1. ubuntu_deployer - Prepares your local machine with packages and configuration required
2. resources - Retrieves all the required resources from other git repos and download locations and sets them up on your local machine
3. iac - Creates the specified infrastructure in your Azure subscription to support the SAS Software deployment (using Terraform)
4. viya - Deploys the SAS software (With Kustomize and kubectl)

### Troubleshooting

In general the scripts provide meaningful error messaging. If a step clearly fails to complete successfully in the execution of a script, it is unlikely that subsequent steps will succeed. Read the error message, understand what it is saying and what could be causing the problem and try to take corrective action, then run the failed script again.

The aim is to build tasks in each script that are idempotent, such that re-running would not break anything. However strictly adhering to  this ideal is an ongoing challenge.



## Authors

[Isaac Marsh](mailto:Isaac.Marsh@sas.com)

## Version History

