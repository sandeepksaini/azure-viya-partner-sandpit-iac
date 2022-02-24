# Azure Viya CA Env IAC
[Link](https://gitlab.sas.com/ssaima/azure-viya-ca-env-iac)

Full Infrastructure and software deployment orchestration for SAS Viya 4 on Azure K8s.
Use-case: Create a dedicated Azure K8s deployment of SAS Viya 4 for the purposes of a Partner Sandpit. Capably sized and deployable in 24 hours.


## Description

The aim of the Azure Viya CA Env IAC is to enable fast deployment of SAS Viya (4) deployed on Azure Kubernetes Service (AKS).
I have utilized the existing automation in these awesome repositories:

https://github.com/sassoftware/viya4-iac-azure

https://github.com/sassoftware/viya4-deployment

As changes are made and improvements/features are added they may or may not seamlessly merge. Work to include new components that require configuration may continue in the future if there is value seen in doing so.

The default config files deploy the the environment with the following configuration:

* Multiple node pools (stateless, stateful, cas, compute, connect)
* Default Internal “Crunchy” PostgreSQL DB
* OpenLDAP for independent management of all users and groups
* NFS Server for application and user (home) data

Variables files allow you to vary the specification of the infrastructure easily (see below)

## Getting Started
### Set Up Prerequisites

### Dependencies
* You must have an Azure subscription to which you (your own Azure login) have authority to create Service Principals with Contributor roles
* Being the Owner of your own Azure subscription is the target use-case here
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
*core-variables.yaml* MUST be edited with your own details, git credentials for SAS gitlab, your Azure subscription details and two central variables you need to choose:
    {deployment_name} - The label stem for many of the infrastructure and resources and the
    {deployment_environment} - The environment name for THIS Viya 4 deployment and the name of the kubernetes namespace for it.

It is IMPORTANT that BOTH of these variables conform to a few rules:
* Eleven (11) characters or less so that all the derived fields have names that are not too long.
* start with a lower-case letter
* only contain letters, numbers and dash (-)
* must not end with a dash

```
cd azure-viya-ca-env-iac
vi core-variables.yaml
```

When your deployment is complete, the environment will be accessed on the URL {deployment_environment}-{deployment_name}.{azure_location}.cloudapp.azure.com. So as an example, I use my SAS short ID as my *deployment_name* and a simple short name indicating the Viya environment's purpose like *proving*, making the URL:
    *proving-ssaima.australiaeast.cloudapp.azure.com*
This is to facilitate deploying multiple environments to a single set of kubernetes infrastructure, as well as deploying other adjacent services to explore integration.


There are four scripts that each must be run  to complete the process, each with its own folder also containing a variables yaml file.
*resources/deployment_repo-variables.yaml* MUST be edited with your own software order information.
```
vi resources/deployment_repo-variables.yaml
```

All other variables files contain current tested default values. These can be customized to your requirement but changes to client software versions (such as ansible, kubectl or terraform) can cause issues that will need manual troubleshooting and intervention.


#### Step 3 - Run scripts in sequence

1. ubuntu_deployer - Prepares your local machine with packages and configuration required
```
./ubuntu_deployer/ubuntu_deployer-setup.sh
```
2. resources - Retrieves all the required resources from other git repos and download locations and sets them up on your local machine
```
./resources/deployment_repo-setup.bash
```
3. iac - Creates the specified infrastructure in your Azure subscription to support the SAS Software deployment (using Terraform)
```
./iac/iac_build.bash
```
4. viya - Deploys the SAS software (With Kustomize and kubectl)
```
./viya/viya-deployment.bash
```

### Done!

Well, YOU are at least. The system itself is working hard still..
You should get a message once deployment is complete with a URL and credentials to log in. However, your SAS pods are still getting scheduled and starting up on the set of node pools and this will still take some time to complete. Each of the nodes must download the container images from the SAS repository for each of the pods it's running. Bandwidth limits the speed that this can occur, so although you've done your bit the deployment still has a fair amount to work through.

## Troubleshooting

In general the scripts provide meaningful error messaging. If a step clearly fails to complete successfully in the execution of a script, it is unlikely that subsequent steps will succeed. Read the error message, understand what it is saying and what could be causing the problem and try to take corrective action, then run the failed script again.

The aim is to build tasks in each script that are idempotent, such that re-running would not break anything. However strictly adhering to this ideal is an ongoing challenge.


## This is where the Automation Ends...

Now that you have a Viya deployment, you need to look after it. I've put a few scripts and snippets here that I use to help you out:

#### Shell Environment

```
~/pyenv_ssaima/bin/activate
```
(This is the example for my environment, substitute ssaima with your $deployment_name.)
A lot of the client tools use python and the cleanest way to maintain dependencies is to use a virtual environment. One has been set up during the deployment and it is for THIS deployment specifically (has all the right versions). Whenever you log on to administer this environment you should first activate  using the binary

```
source source_all.bash
```
This simply sources all the variables used in the deployment for use in your current shell. Very helpful if you have multiple environments as you can use shell parameterized commands with automatic substitution. Below are some of these examples.

#### Watch the deployment start
```
kubectl get pods -o wide -n ${deployment_environment}
```
See all the pods starting up and look for issues and errors.

#### Making changes

The artifacts, repos and configuration written by the four scripts is placed in your home folder named *$(deployment_name)-aks*
```
cd ~/$(deployment_name)-aks
```
Inside this folder there are many folders and files now. The *viya4-iac-azure* folder is the cloned repo for the sassoftware github Infrastructure-As-Code, with edits made specific to your deployment. Here you can add, edit and apply changes using terraform as you might with any other Viya deployment.

Re-generate the Terraform plan after making changes to the infrastructure specification (eg. adding more nodes to a pool)
```
# Don't forget to setup your shell with python virtual env and shell environment variables
~/pyenv_ssaima/bin/activate
source $HOME/azure-viya-ca-env-iac/source_all.bash

cd $HOME/${deployment_name}-aks/viya4-iac-azure

# DO SOME CHANGES IN HERE THAT NEED A NEW TERRAFORM PLAN
#   eg. I might edit ssaima.tfvars to change the cas node_pool to have "max_nodes" = "4" for added capacity

# Create the updated terraform plan
terraform plan -input=false \
    -var-file=./${deployment_name}.tfvars \
    -out ./${deployment_name}-aks.plan

cd $HOME/${deployment_name}-aks/viya4-iac-azure
TFPLAN=${deployment_name}-aks.plan

# Apply the terraform plan
time terraform apply "./${TFPLAN}" 2>&1 \
| tee -a $HOME/${deployment_name}-aks/viya4-iac-azure/$(date +%Y%m%dT%H%M%S)_terraform-apply.log

# After this you may need to regenerate your kube_config file
terraform output kube_config | sed '1d;$d' > ~/.kube/${deployment_name}-aks-kubeconfig.conf
kubectl config set-context --current --namespace=${deployment_environment}

```

The $deployment_environment folder (eg. *proving* for my example) contains the kubernetes configuration for your Viya software environment. In here you can add and remove resources, configurations, transformers, generators and components into the site-config folder, and corresponding references in kustomization.yaml to change the kubernetes deployment.
There is much more detail about how this all works in the SAS Viya Operations Guide for your chosen software version. Additionally, read up on how this folder was generated using viya4-deployment at the [viya4-deployment sassoftware Github page](https://github.com/sassoftware/viya4-deployment)

```
cd $HOME/${deployment_name}-aks/${deployment_environment}/

# DO SOME CONFIG CHANGES IN HERE

kustomize build -o site.yaml

kubectl apply -f site.yaml
```

## Destroy Everything!!

So you're done and now you need to get rid of it all? Forever? Irretrievably?
Simple, you just need to create a terraform "destroy" plan:

```
# Generate the DESTROY plan
cd $HOME/${deployment_name}-aks/viya4-iac-azure
terraform plan -input=false \
    -destroy \
    -var-file=./$deployment_name.tfvars \
    -out ./$deployment_name-aks-destroy.plan

# Run the DESTROY plan
echo "[INFO] Destroying the AKS cluster infra"
time terraform apply $deployment_name-aks-destroy.plan 2>&1 \
| tee -a $HOME/${deployment_name}-aks/viya4-iac-azure/$(date +%Y%m%dT%H%M%S)_terraform-destroy.log
```

All gone!

(If not you can always log into portal.azure.com and delete the two resource groups that bear your ${deployment_name})


## Authors

[Isaac Marsh](mailto:Isaac.Marsh@sas.com)

## Version History
