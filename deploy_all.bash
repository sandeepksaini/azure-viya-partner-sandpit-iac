#!/bin/bash
## VIYA DEPLOYER - AZURE K8S ##
###############
## FUNCTIONS ##
###############


# Usage function
function usage {
    echo "something went wrong..."
    exit 0;
}

## pid file management #####################
script_basename=`basename "$0" | sed 's/\(.*\)\..*/\1/'`
PIDFILE=/var/run/$script_basename.pid

if [ -f $PIDFILE ]
then
  PID=$(cat $PIDFILE)
  ps -p $PID > /dev/null 2>&1
  if [ $? -eq 0 ]
  then
    echo "Process already running"
    exit 1
  else
    ## Process not found assume not running
    echo $$ > $PIDFILE
    if [ $? -ne 0 ]
    then
      echo "Could not create PID file"
      exit 1
    fi
  fi
else
  echo $$ > $PIDFILE
  if [ $? -ne 0 ]
  then
    echo "Could not create PID file"
    exit 1
  fi
fi
## pid file management ####################

# Check number of arguements  = 1 or 0
if [ $# -ne 1 ];
then
    if [ $# -ne 0 ]
    then
        usage;
        exit 1;
    fi
fi

## https://gist.github.com/masukomi/e587aa6fd4f042496871
# Here is a bash-only YAML parser that leverages sed and awk to parse simple yaml files:
function parse_yaml {
   local prefix=$2 # accepts a prefix argument so that imported settings all have a common prefix (which will reduce the risk of namespace collisions)
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}
# typical use within a script is:
#   eval $(parse_yaml sample.yml)


# Function to check the presence of a directory
function chkdir {
# Returns 0 if first parameter is a valid path to a directory
    if [[ -d $1 ]]; then
        return 0;
    else
        return 1;
    fi
}

function chkfile {
# Returns 0 if first parameter is a valid path to a regular file
    if [[ -f $1 ]]; then
        return 0;
    else
        return 1;
    fi
}


# Source default configuration
# if chkfile $script_path/default.yml;
if chkfile ~/deployment_variables.yaml;
then
    # eval $(parse_yaml $script_path/default.yml)
	eval $(parse_yaml ~/deployment_variables.yaml)
fi

# # Source site configuration
# if chkfile $1;
# then
    # eval $(parse_yaml $1)
	
# fi

##################
# Update the public access IP variables with this machine's IP
MYIP=$(curl https://ifconfig.me)
if [[ $deployment_iac_azure_network_defaultpublicaccesscidrs == *"$MYIP"* ]]; then
  echo "Current IP already present - $deployment_iac_azure_network_defaultpublicaccesscidrs"
else
	deployment_iac_azure_network_defaultpublicaccesscidrs=$(echo $deployment_iac_azure_network_defaultpublicaccesscidrs | sed -re 's/\[(.*)\]/\[\1,\"'$MYIP'\/32\"\]/')
fi
if [[ $deployment_iac_viya4deployment_ingress_sourceranges == *"$MYIP"* ]]; then
	echo "Current IP already present - $deployment_iac_viya4deployment_ingress_sourceranges"
else
	deployment_iac_viya4deployment_ingress_sourceranges=$(echo $deployment_iac_viya4deployment_ingress_sourceranges | sed -re 's/\[(.*)\]/\[\1,\"'$MYIP'\/32\"\]/')
fi
##################


echo "Starting deployment of $deployment_name Envrionment"

# Install pre-requisite OS packages
sudo apt-get update && sudo apt-get install -y \
    python3-pip \
    zip \
    curl \
    git \
    jq \
    nfs-common \
    portmap \
    unzip
	

ansible localhost -m lineinfile -a "dest=~/.bashrc line='alias python=python3'" --diff
ansible localhost -m lineinfile -a "dest=~/.bashrc line='alias pip=pip3'" --diff
pip3 install --upgrade pip

echo "[INFO] installing azure-cli $deployment_deployervm_client_azurecli_version..."
pip3 install azure-cli==${deployment_deployervm_client_azurecli_version}

echo "[INFO] installing ansible $deployment_deployervm_client_ansible_version..."
pip3 install ansible==${deployment_deployervm_client_ansible_version}

echo "[INFO] installing terraform $deployment_deployervm_client_terraform_version..."
mkdir -p /usr/bin
cd /usr/bin
sudo rm -Rf /usr/bin/terraform
sudo curl -o terraform.zip -s https://releases.hashicorp.com/terraform/${deployment_deployervm_client_terraform_version}/terraform_${deployment_deployervm_client_terraform_version}_linux_amd64.zip
sudo unzip terraform.zip && sudo rm -f terraform.zip
export PATH=$PATH:/usr/bin
/usr/bin/terraform version

# Install yq
wget https://github.com/mikefarah/yq/releases/download/${deployment_deployervm_client_yq_version}/${deployment_deployervm_client_yq_binary} -O /usr/bin/yq &&\
    chmod +x /usr/bin/yq
/usr/bin/yq --version

# Members of the Helm community have contributed a Helm package for Apt. This package is generally up to date.
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
sudo apt-get install apt-transport-https --yes
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

# Install kubectl
sudo curl -LO "https://dl.k8s.io/release/v${deployment_deployervm_client_kubectl_version}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/bin/kubectl

##################################################
## Authenticate with Azure
az login --use-device-code
## NOTE You need to do stuff interactively here to log in as you (with owner permissions)
# 
##################################################

# Set Location & Subscription
echo "[INFO] Setting default location to $deployment_iac_azure_location"
az configure --defaults location=$deployment_iac_azure_location
az account set -s "$deployment_iac_azure_subscription"


## Mount the deployment resources File Share
sudo mkdir /deployment_resources
sudo chown viyadeployer /deployment_resources
# This command assumes you have logged in with az login
httpEndpoint=$(az storage account show \
    --resource-group $deployment_deployervm_azureresourcegroup \
    --name $deployment_deployervm_azurestorageaccount \
    --query "primaryEndpoints.file" | tr -d '"')
echo $httpEndpoint
deployment_deploymentresources_filesharesmbPath=$(echo $httpEndpoint | cut -c7-$(expr length $httpEndpoint))$deployment_deploymentresources_filesharename
echo $deployment_deploymentresources_filesharesmbPath
storageAccountKey=$(az storage account keys list \
    --resource-group $deployment_deployervm_azureresourcegroup \
    --account-name $deployment_deployervm_azurestorageaccount \
    --query "[0].value" | tr -d '"')

# Save Creds & Set automount
echo "username=$deployment_deployervm_azurestorageaccount" | tee /home/viyadeployer/.azureStorageAccCreds > /dev/null
echo "password=$storageAccountKey" | tee -a /home/viyadeployer/.azureStorageAccCreds > /dev/null
sudo chmod 600 /home/viyadeployer/.azureStorageAccCreds
if [ -z "$(grep $deployment_deploymentresources_filesharesmbPath /etc/fstab)" ]; then
    echo "$deployment_deploymentresources_filesharesmbPath/ /deployment_resources cifs nofail,vers=3.0,credentials=/home/viyadeployer/.azureStorageAccCreds,serverino,uid=1000,gid=1000 0 0" | sudo tee -a /etc/fstab > /dev/null
else
    echo "/etc/fstab was not modified to avoid conflicting entries as this Azure file share was already present"
fi
sudo mount -a
## MANUAL MOUNT
#sudo mount -t cifs "$deployment_deploymentresources_filesharesmbPath/" /deployment_resources -o username=$deployment_deployervm_azurestorageaccount,password=$storageAccountKey,serverino,uid=1000,gid=1000


## Obtain the Terraform templates from https://github.com/sassoftware/viya4-iac-azure/releases
# Note that this was last built from 1.0.1 and this is now 3.0.0 which includes updates to several component versions including terraform critically
mkdir -p /deployment_resources/aks
cd /deployment_resources/aks/
git clone https://github.com/sassoftware/viya4-iac-azure.git

# Instead of being at the mercy of the latest changes, we pin to a specific version
cd viya4-iac-azure/
git fetch --all
git checkout tags/${deployment_iac_viya4iacazure_iacazuretag}


# Create an Azure Service Principal for Terraform
TFCREDFILE=/deployment_resources/TF_CLIENT_CREDS
if [ ! -f "$TFCREDFILE" ]; then
  SP_PASSWD=$(az ad sp create-for-rbac --skip-assignment --name http://${deployment_name} --query password --output tsv)
  SP_APPID=$(az ad sp show --id http://${deployment_name} --query appId --output tsv)
  # give the "Contributor" role to your Azure SP
  # You only have to do it once !
  az role assignment create --assignee $SP_APPID --role Contributor
fi

# export the required values in TF required environment variables 
export TF_VAR_subscription_id=$(az account list --query "[?name=='$deployment_iac_azure_subscription'].{id:id}" -o tsv)
export TF_VAR_tenant_id=$(az account list --query "[?name=='$deployment_iac_azure_subscription'].{tenantId:tenantId}" -o tsv)
export TF_VAR_client_id=${SP_APPID}
export TF_VAR_client_secret=${SP_PASSWD}

printf "TF_VAR_subscription_id   -->   ${TF_VAR_subscription_id}
TF_VAR_tenant_id         -->   ${TF_VAR_tenant_id}
TF_VAR_client_id      -->   ${TF_VAR_client_id}
TF_VAR_client_secret  -->   ${TF_VAR_client_secret}\n"

# save the TF environment variables value for the next time
tee /deployment_resources/TF_CLIENT_CREDS > /dev/null << EOF
export TF_VAR_subscription_id=${TF_VAR_subscription_id}
export TF_VAR_tenant_id=${TF_VAR_tenant_id}
export TF_VAR_client_id=${TF_VAR_client_id}
export TF_VAR_client_secret=${TF_VAR_client_secret}
EOF
chmod u+x /deployment_resources/TF_CLIENT_CREDS
. /deployment_resources/TF_CLIENT_CREDS

# Force TF_CLIENT_CREDS to run next time we re-login
ansible localhost -m lineinfile -a "dest=~/.bashrc line='source /deployment_resources/TF_CLIENT_CREDS'" --diff

cd /deployment_resources/aks/viya4-iac-azure
#terraform init
terraform init


#######################
#### PROIVISIONING ####
#######################

# ensure there is a .ssh dir in $HOME - Don't think this is required if we are running in a VM already setup with ssh?
# ansible localhost -m file \
    # -a "path=$HOME/.ssh mode=0700 state=directory"

# get azure user email address
az ad signed-in-user show --query userPrincipalName \
| sed  's|["\ ]||g' \
| tee ~/.email.txt
# store email address in a variable to use later in TF variable
EMAIL=$(cat ~/.email.txt)

# Populate the TF variables file
# Ref: https://github.com/sassoftware/viya4-iac-azure/blob/main/docs/CONFIG-VARS.md

tee /deployment_resources/aks/viya4-iac-azure/$deployment_name.tfvars > /dev/null << EOF
#### REQUIRE VARIABLES ####
prefix                               = "${deployment_name}-viya4aks"
location                             = "${deployment_iac_azure_location}"
ssh_public_key                       = "/home/viyadeployer/.ssh/viyadeployer.pub"
#### General config ####
kubernetes_version                   = "1.19.11"
# no jump host machine
create_jump_vm                       = "false"
create_jump_public_ip                = "false"
# tags in azure
tags                                 = { "resourceowner" = "${EMAIL}" , project_name = "${deployment_name}", environment = "${deployment_environment}" }
#### Azure Auth ####
# not required if already set in TF environment variables?
# tenant_id                            = ${TENANT_ID}
# subscription_id                      = ${SUBSCRIPTION_ID}
# client_id                            = ${CLIENT_ID}
# client_secret                        = ${CLIENT_SECRET}
#### Admin Access ####
# IP Ranges allowed to access all created cloud resources
default_public_access_cidrs         = ${deployment_iac_azure_network_defaultpublicaccesscidrs}
#### Storage ####
# "dev" creates AzureFile, "standard" creates NFS server VM, "ha" creates Azure Netapp Files
storage_type                         = "standard"
create_nfs_public_ip                 = "${deployment_iac_viya4iacazure_storage_nfs_publicip}"
nfs_vm_admin                         = "${deployment_iac_viya4iacazure_storage_nfs_adminuser}"
nfs_vm_machine_type                  = "${deployment_iac_viya4iacazure_storage_nfs_vm_machinetype}"
nfs_vm_zone                          = "${deployment_iac_viya4iacazure_storage_nfs_vm_zone}"
nfs_raid_disk_type                   = "${deployment_iac_viya4iacazure_storage_nfs_raid_disktype}"
nfs_raid_disk_size                   = "${deployment_iac_viya4iacazure_storage_nfs_raid_disksize}"
nfs_raid_disk_zones                  = ${deployment_iac_viya4iacazure_storage_nfs_raid_diskzones}
#### Default Nodepool ####
default_nodepool_vm_type             = "Standard_D4_v4"
default_nodepool_min_nodes           = 1
default_nodepool_os_disk_size        = 64
node_pools_proximity_placement       = false
default_nodepool_availability_zones  = ["1"]
node_pools_availability_zone         = "1"
#### AKS Node Pools config ####
node_pools = {
    cas = {
        "machine_type" = "${deployment_iac_viya4iacazure_nodepools_cas_machinetype}"
        "os_disk_size" = "${deployment_iac_viya4iacazure_nodepools_cas_osdisksize}"
        "min_nodes" = "${deployment_iac_viya4iacazure_nodepools_cas_minnodes}"
        "max_nodes" = "${deployment_iac_viya4iacazure_nodepools_cas_maxnodes}"
        "max_pods" = "${deployment_iac_viya4iacazure_nodepools_cas_maxpods}"
        "node_taints" = ["workload.sas.com/class=cas:NoSchedule"]
        "node_labels" = {
            "workload.sas.com/class" = "cas"
        }
    },
    compute = {
        "machine_type" = "${deployment_iac_viya4iacazure_nodepools_compute_machinetype}"
        "os_disk_size" = "${deployment_iac_viya4iacazure_nodepools_compute_osdisksize}"
        "min_nodes" = "${deployment_iac_viya4iacazure_nodepools_compute_minnodes}"
        "max_nodes" = "${deployment_iac_viya4iacazure_nodepools_compute_maxnodes}"
        "max_pods" = "${deployment_iac_viya4iacazure_nodepools_compute_maxpods}"
        "node_taints" = ["workload.sas.com/class=compute:NoSchedule"]
        "node_labels" = {
            "workload.sas.com/class"        = "compute"
            "launcher.sas.com/prepullImage" = "sas-programming-environment"
        }
    },
    connect = {
        "machine_type" = "${deployment_iac_viya4iacazure_nodepools_connect_machinetype}"
        "os_disk_size" = "${deployment_iac_viya4iacazure_nodepools_connect_osdisksize}"
        "min_nodes" = "${deployment_iac_viya4iacazure_nodepools_connect_minnodes}"
        "max_nodes" = "${deployment_iac_viya4iacazure_nodepools_connect_maxnodes}"
        "max_pods" = "${deployment_iac_viya4iacazure_nodepools_connect_maxpods}"
        "node_taints" = ["workload.sas.com/class=connect:NoSchedule"]
        "node_labels" = {
            "workload.sas.com/class"        = "connect"
            "launcher.sas.com/prepullImage" = "sas-programming-environment"
        }
    },
    stateless = {
        "machine_type" = "${deployment_iac_viya4iacazure_nodepools_stateless_machinetype}"
        "os_disk_size" = "${deployment_iac_viya4iacazure_nodepools_stateless_osdisksize}"
        "min_nodes" = "${deployment_iac_viya4iacazure_nodepools_stateless_minnodes}"
        "max_nodes" = "${deployment_iac_viya4iacazure_nodepools_stateless_maxnodes}"
        "max_pods" = "${deployment_iac_viya4iacazure_nodepools_stateless_maxpods}"
        "node_taints" = ["workload.sas.com/class=stateless:NoSchedule"]
        "node_labels" = {
            "workload.sas.com/class" = "stateless"
        }
    },
    stateful = {
        "machine_type" = "${deployment_iac_viya4iacazure_nodepools_stateful_machinetype}"
        "os_disk_size" = "${deployment_iac_viya4iacazure_nodepools_stateful_osdisksize}"
        "min_nodes" = "${deployment_iac_viya4iacazure_nodepools_stateful_minnodes}"
        "max_nodes" = "${deployment_iac_viya4iacazure_nodepools_stateful_maxnodes}"
        "max_pods" = "${deployment_iac_viya4iacazure_nodepools_stateful_maxpods}"
        "node_taints" = ["workload.sas.com/class=stateful:NoSchedule"]
        "node_labels" = {
            "workload.sas.com/class" = "stateful"
        }
    }
}
#### Azure Postgres config ####
# # set this to "false" when using internal Crunchy Postgres and Azure Postgres is NOT needed
create_postgres                  = true
postgres_server_version          = "${deployment_iac_viya4iacazure_azurepostgres_version}"
postgres_sku_name                = "${deployment_iac_viya4iacazure_azurepostgres_skuname}"
postgres_storage_mb              = "${deployment_iac_viya4iacazure_azurepostgres_storagemb}"
postgres_backup_retention_days   = "${deployment_iac_viya4iacazure_azurepostgres_daysofbackup}"
postgres_administrator_login     = "${deployment_iac_viya4iacazure_azurepostgres_adminlogin}"
postgres_administrator_password  = "${deployment_iac_viya4iacazure_azurepostgres_adminpassword}"
postgres_ssl_enforcement_enabled = true
#### Azure Container Registry ####
create_container_registry           = false
container_registry_sku              = "Standard"
container_registry_admin_enabled    = "true"
container_registry_geo_replica_locs = null
EOF



# Adjustment to add the required paths for the nfs-clients to connect
cat > ./addNFSstructure.yml << EOF
---
- hosts: localhost
  tasks:
  - name: Create NFS folder structure config
    blockinfile:
      path: /deployment_resources/aks/viya4-iac-azure/files/cloud-init/nfs/cloud-config
      insertafter: EOF
      marker: "  # {mark} ANSIBLE MANAGED BLOCK : base folder structure creation"
      block: |2
          - mkdir -p /export/pvs /export/proving1/bin
          - mkdir /export/proving1/data
          - mkdir /export/proving1/homes
          - mkdir /export/proving1/astores
EOF

## APPLY
ansible-playbook ./addNFSstructure.yml --diff


# outputs.tf 
# To avoid :
# ╷
# │ Error: Output refers to sensitive values
# │
# │   on outputs.tf line 90:
# │   90: output "cr_admin_password" {
# │
# │ To reduce the risk of accidentally exporting sensitive data that was intended to be only internal, Terraform requires that any root module output containing sensitive data be explicitly marked as sensitive, to confirm your intent.
# │
# │ If you do intend to export this data, annotate the output value as sensitive by adding the following argument:
# │     sensitive = true


# Generate the TF plan corresponding to the AKS cluster with multiple node pools
cd /deployment_resources/aks/viya4-iac-azure
terraform plan -input=false \
    -var-file=./$deployment_name.tfvars \
    -out ./$deployment_name-aks.plan
	
#    <<<< YOU ARE HERE

##################################################
##### Deploy the AKS cluster with the TF plan ####
##################################################
cd /deployment_resources/aks/viya4-iac-azure
TFPLAN=$deployment_name-aks.plan
#terraform show ${TFPLAN}
time terraform apply "./${TFPLAN}" 2>&1 \
| tee -a /deployment_resources/aks/viya4-iac-azure/$(date +%Y%m%dT%H%M%S)_terraform-apply.log
##################################################

# Generate the config file with a recognizable name
mkdir -p ~/.kube
terraform output kube_config | sed '1d;$d' > ~/.kube/${deployment_name}-aks-kubeconfig.conf

SOURCEFILE=~/.kube/${deployment_name}-aks-kubeconfig.conf
ansible localhost -m file \
  -a "src=$SOURCEFILE \
      dest=~/.kube/config state=link" \
  --diff

# Set the kubeconfig directory 
export KUBECONFIG=~/.kube/config
ansible localhost \
    -m lineinfile \
    -a "dest=~/.bashrc \
        line='export KUBECONFIG=~/.kube/config' \
        state=present" \
    --diff


# See nodes created
kubectl get nodes

# Disable the authorized IP range for the Kubernetes API
az aks update -n ${deployment_name}-viya4aks-aks \
    -g ${deployment_name}-viya4aks-rg --api-server-authorized-ip-ranges ""
    
# Configure kubectl auto-completion
source <(kubectl completion bash)
ansible localhost \
    -m lineinfile \
    -a "dest=~/.bashrc \
        line='source <(kubectl completion bash)' \
        state=present" \
    --diff


########################################################################
##                           VIYA DEPLOYMENT                          ##
########################################################################
# https://github.com/sassoftware/viya4-deployment.git

########################
### PRE-REQUISITES #####
########################

# create the deployments folder
mkdir -p /deployment_resources/deployments/${deployment_name}-viya4aks-aks/

cd /deployment_resources/
git clone https://github.com/sassoftware/viya4-deployment.git
cd viya4-deployment
# Instead of being at the mercy of the latest changes, we pin to a specific version
git fetch --all
git checkout tags/${deployment_iac_viya4deployment_versiontag}


# Update the requirements files to align with your versions
cd /deployment_resources/viya4-deployment/
sed -i.bak -re 's/ansible==.*/ansible=='"$deployment_deployervm_client_ansible_version"'/' requirements.txt
## THIS COULD BREAK EVERYTHING ##

# install python packages
pip3 install --user -r requirements.txt

# install ansible collections
ansible-galaxy collection install -r requirements.yaml -f

# Create viya4-deployment customization folder structure
#    <base_dir>            <- parent directory
#      /<cluster>          <- folder per cluster
#        /<namespace>      <- folder per namespace
#          /site-config    <- location for all customizations
#            ...           <- folders containing user defined customizations
mkdir -p /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config

### VIya Orders CLI
# https://github.com/sassoftware/viya4-orders-cli/releases/download/1.0.0/viya4-orders-cli_linux_amd64
# Retrieve viya4-orders-cli
ansible localhost \
    -m get_url -a \
"url=https://github.com/sassoftware/viya4-orders-cli/releases/download/${deployment_deployervm_client_viya4ordercli_version}/viya4-orders-cli_linux_amd64 \
        dest=/tmp/viya4-orders-cli \
        validate_certs=no \
        force=yes \
        mode=0755 \
        backup=yes" \
    --diff
sudo mv /tmp/viya4-orders-cli /usr/bin/viya4-orders-cli
sudo chmod 777 /usr/bin/viya4-orders-cli
viya4-orders-cli -v
# Set API client credentials
CLIENTCREDENTIALSID=$(echo -n ${deployment_viya4_orderapikey} | base64)
CLIENTCREDENTIALSSECRET=$(echo -n ${deployment_viya4_orderapisecret} | base64)
tee $HOME/.viya4-orders-cli > /dev/null << EOF
clientCredentialsId: ${CLIENTCREDENTIALSID}
clientCredentialsSecret: ${CLIENTCREDENTIALSSECRET}
EOF

# Download Order
mkdir -p /deployment_resources/deployments/${deployment_name}-viya4aks-aks/orders/${deployment_viya4_ordernumber}/
pushd /deployment_resources/deployments/${deployment_name}-viya4aks-aks/orders/${deployment_viya4_ordernumber}/
viya4-orders-cli certificates ${deployment_viya4_ordernumber}
viya4-orders-cli license ${deployment_viya4_ordernumber} ${deployment_viya4_cadencename} ${deployment_viya4_cadenceversion}
viya4-orders-cli deploymentAssets ${deployment_viya4_ordernumber} ${deployment_viya4_cadencename} ${deployment_viya4_cadenceversion}
#set path variables
deployment_viya4_certpath=$(readlink -f /deployment_resources/deployments/${deployment_name}-viya4aks-aks/orders/${deployment_viya4_ordernumber}/*${deployment_viya4_ordernumber}_certs.zip)
deployment_viya4_licensepath=$(readlink -f /deployment_resources/deployments/${deployment_name}-viya4aks-aks/orders/${deployment_viya4_ordernumber}/*${deployment_viya4_ordernumber}_${deployment_viya4_cadencename}_${deployment_viya4_cadenceversion}_license*.jwt)
deployment_viya4_assetspath=$(ls -1 /deployment_resources/deployments/${deployment_name}-viya4aks-aks/orders/${deployment_viya4_ordernumber}/SASViyaV4_${deployment_viya4_ordernumber}_${deployment_viya4_cadencename}_${deployment_viya4_cadenceversion}*.tgz | tail -n1)
#deployment_viya4_assetspath=$(readlink -f /deployment_resources/deployments/${deployment_name}-viya4aks-aks/orders/${deployment_viya4_ordernumber}/*${deployment_viya4_ordernumber}_${deployment_viya4_cadencename}_${deployment_viya4_cadenceversion}*.tgz)

### Setup Azure Container Registry
mkdir -p /deployment_resources/aks/containerReg
az acr create \
  --resource-group ${deployment_deployervm_azureresourcegroup} \
  --name ViyaContainerRegistry \
  --sku Basic \
  --admin-enabled true
  | tee /deployment_resources/aks/containerReg/acr.json
## NEED TO TEST IF ADMIN ID AND PASSWORD ARE PROVIDED ON CREATE AND STORE THEM
deployment_resources_acrname=$(jq -r '.name' /deployment_resources/aks/containerReg/acr.json)
deployment_resources_acrloginserver=$(jq -r '.loginServer' /deployment_resources/aks/containerReg/acr.json)
#deployment_resources_acrloginserver="${deployment_name}viya4aksacr.azurecr.io"
deployment_resources_acrtoken=$(az acr login --name ${deployment_resources_acrname} --expose-token | jq -r '.accessToken')

ansible localhost \
    -m get_url -a \
    "url=https://support.sas.com/installation/viya/4/sas-mirror-manager/lax/mirrormgr-linux.tgz \
        dest=/tmp/mirrormgr-linux.tgz \
        validate_certs=no \
        force=yes \
        mode=0755 \
        backup=yes" \
    --diff
mkdir -p /deployment_resources/mirrormgr
cd /deployment_resources/mirrormgr
tar -xzvf /tmp/mirrormgr-linux.tgz

# Mirror order to the local registry
/deployment_resources/mirrormgr/mirrormgr mirror registry \
--deployment-data ${deployment_viya4_certpath} \
--destination ${deployment_resources_acrloginserver} \
--cadence ${deployment_viya4_cadencename}-${deployment_viya4_cadenceversion} \
--username 00000000-0000-0000-0000-000000000000 --password ${deployment_resources_acrtoken} \
--workers 5 \
--path /deployment_resources/sas_repos/

## Servioce Principle for Pull
deployment_resources_acrspname="${deployment_resources_acrname}-pull-SP"
# Obtain the full registry ID for subsequent command args
deployment_resources_acrid=$(az acr show --name ${deployment_resources_acrname} --query id --output tsv)

# Create the service principal with rights scoped to the registry.
# Default permissions are for docker pull access. Modify the '--role'
# argument value as desired:
# acrpull:     pull only
# acrpush:     push and pull
# owner:       push, pull, and assign roles
deployment_resources_acrsppwd=$(az ad sp create-for-rbac --name $deployment_resources_acrspname --scopes $deployment_resources_acrid --role acrpull --query password --output tsv)
deployment_resources_acrspid=$(az ad sp list --display-name $deployment_resources_acrspname --query [].appId --output tsv)
# Output the service principal's credentials; use these in your services and
# applications to authenticate to the container registry.
printf "Service principal ID: deployment_resources_acrspid --> ${deployment_resources_acrspid}
Service principal password: deployment_resources_acrsppwd --> ${deployment_resources_acrsppwd}\n"

# save the Service Principle ENV VARS
tee /deployment_resources/deployments/${deployment_name}-viya4aks-aks/SP_CREDS > /dev/null << EOF
export TF_VAR_subscription_id=${TF_VAR_subscription_id}
export TF_VAR_tenant_id=${TF_VAR_tenant_id}
export TF_VAR_client_id=${TF_VAR_client_id}
export TF_VAR_client_secret=${TF_VAR_client_secret}
EOF
chmod u+x /deployment_resources/deployments/${deployment_name}-viya4aks-aks/SP_CREDS
. /deployment_resources/deployments/${deployment_name}-viya4aks-aks/SP_CREDS

# Force TF_CLIENT_CREDS to run next time we re-login
ansible localhost -m lineinfile -a "dest=~/.bashrc line='source /deployment_resources/deployments/${deployment_name}-viya4aks-aks/SP_CREDS'" --diff



# viya4-deployment IAC Manifest
tee /deployment_resources/deployments/${deployment_name}-viya4aks-aks/ansible-vars-iac_manifests.yaml > /dev/null << EOF
## Cluster
NAMESPACE: ${deployment_environment}

## MISC
DEPLOY: false # Set to false to stop at generating the manifest
LOADBALANCER_SOURCE_RANGES: ${deployment_iac_viya4deployment_ingress_sourceranges}

## Storage
V4_CFG_MANAGE_STORAGE: true

# ## SAS API Access
V4_CFG_SAS_API_KEY: ${deployment_viya4_orderapikey}
V4_CFG_SAS_API_SECRET: ${deployment_viya4_orderapisecret}
V4_CFG_ORDER_NUMBER:  ${deployment_viya4_ordernumber}
V4_CFG_CADENCE_NAME: ${deployment_viya4_cadencename}
V4_CFG_CADENCE_VERSION: ${deployment_viya4_cadenceversion}

V4_CFG_DEPLOYMENT_ASSETS: ${deployment_viya4_assetspath}
V4_CFG_LICENSE: ${deployment_viya4_licensepath}

## CR Access
# V4_CFG_CR_URL: ${deployment_resources_acrloginserver}
# V4_CFG_CR_USER: ${deployment_resources_acrspname}
# V4_CFG_CR_PASSWORD: ${deployment_resources_acrsppwd}

## Ingress
V4_CFG_INGRESS_TYPE: ingress
V4_CFG_INGRESS_FQDN: "$deployment_environment-$deployment_name.australiaeast.cloudapp.azure.com"
V4_CFG_TLS_MODE: "full-stack" # [full-stack|front-door|disabled]

## Postgres
V4_CFG_POSTGRES_TYPE: external #[internal|external]

## LDAP
V4_CFG_EMBEDDED_LDAP_ENABLE: true

## Consul UI
V4_CFG_CONSUL_ENABLE_LOADBALANCER: false

## SAS/CONNECT
V4_CFG_CONNECT_ENABLE_LOADBALANCER: false

## Monitoring and Logging
## uncomment and update the below values when deploying the viya4-monitoring-kubernetes stack
#V4M_BASE_DOMAIN: adm

## Enable opendistro elasticsearch
V4_CFG_ELASTICSEARCH_ENABLE: true

EOF


#### Setup kustomize
ansible localhost \
    -m get_url -a \
	"url=https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${deployment_deployervm_client_kustomize_version}/kustomize_v${deployment_deployervm_client_kustomize_version}_linux_amd64.tar.gz \
        dest=/tmp/kustomize.tgz \
        validate_certs=no \
        force=yes \
        mode=0755 \
        backup=yes" \
    --diff

cd /tmp/ ; tar xf /tmp/kustomize.tgz

sudo cp /tmp/kustomize /usr/bin/kustomize
sudo chmod 777 /usr/bin/kustomize
kustomize version


## SITE CONFIG
cp -p ${deployment_viya4_licensepath} /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/license.jwt

# Gather required files, then generate Baseline & Viya deployment manifests
cd /deployment_resources/viya4-deployment/
ansible-playbook \
  -e BASE_DIR=/deployment_resources/deployments \
  -e CONFIG=/deployment_resources/deployments/${deployment_name}-viya4aks-aks/ansible-vars-iac_manifests.yaml \
  -e TFSTATE=/deployment_resources/aks/viya4-iac-azure/terraform.tfstate \
  playbooks/playbook.yaml --tags "baseline,viya,install"


## INTERNAL CONTAINER REGISTRY ACCESS
# Following info found here as well:
# https://rndconfluence.sas.com/confluence/display/RLSENG/Accessing+internal+container+images+from+external+locations#Accessinginternalcontainerimagesfromexternallocations-AccessingPulpImageswithaToken
    # Go to this URL:  https://cr.sas.com/tokens
    # Click create to create a new token with the default settings
    # Copy the values for Username and Password and store them securely
    # Open a command prompt on your kubectl system
    # run these commands:
# mkdir /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/cr
# CR_SAS_COM_SECRET="$(kubectl create secret docker-registry cr-access \
  # --docker-server=cr.sas.com \
  # --docker-username=${deployment_viya4_cruser} \
  # --docker-password=${deployment_viya4_crpassword} \
  # --dry-run -o json | jq -r '.data.".dockerconfigjson"')"
# echo -n $CR_SAS_COM_SECRET | base64 --decode > /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/cr/cr_sas_com_access.json


#### Configure to use Mirror Registry
cd /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/
mkdir -p site-config/admin
sed -re "s/\{\{ MIRROR-HOST \}\}/${deployment_resources_acrloginserver}/g" sas-bases/examples/mirror/mirror.yaml > site-config/admin/mirror.yaml
cat > ./azureContainerRepo1.yaml << EOF
---
- hosts: localhost
  tasks:
    - name: "Reference mirror Transformer"
      tags: mirror
      lineinfile:
        path: /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/kustomization.yaml
        line: "  - site-config/admin/mirror.yaml"
        insertafter: "  - sas-bases/overlays/required/transformers.yaml"
        firstmatch: yes
        state: present
EOF

cat > ./azureContainerRepo2.yaml << EOF
---
- hosts: localhost
  tasks:
  - name: "Update configMap"
    blockinfile:
      path: /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/kustomization.yaml
      insertafter: EOF
      marker: "# {mark} ANSIBLE MANAGED BLOCK : Azure Container Registry paths"
      block: |2
        configMapGenerator:
          - name: input 
            behavior: merge
            literals:
            - IMAGE_REGISTRY=${deployment_resources_acrloginserver}
EOF

sed -i "/  - site-config\/admin\/mirror\.yaml/d" /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/kustomization.yaml
ansible-playbook ./azureContainerRepo1.yaml --diff
ansible-playbook ./azureContainerRepo2.yaml --diff

#### AZURE CONTAINER REGISTRY SETUP
#deployment_viya4_azurecr_adminuser='ViyaContainerRegistry'
#deployment_viya4_azurecr_adminpassword='u8A5F=0voyRg0IE4xqlkFMbMg=fbp=Zy'
mkdir -p /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/cr
CR_AZURE_SECRET="$(kubectl create secret docker-registry cr-access \
  --docker-server=${deployment_resources_acrloginserver} \
  --docker-username=${deployment_resources_acrspname} \
  --docker-password=${deployment_resources_acrsppwd} \
  --dry-run=client  -o json | jq -r '.data.".dockerconfigjson"')"
echo -n $CR_AZURE_SECRET | base64 --decode > /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/cr/cr_azure_access.json


# add under under "secretGenerator" into the kustomzation.yaml
cd /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/
cat > ./azureCRSecrets.yml << EOF
---
- hosts: localhost
  tasks:
  - name: secretGenerator sas-image-pull-secrets update
    blockinfile:
      path: /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/kustomization.yaml
      insertafter: EOF
      marker: "# {mark} ANSIBLE MANAGED BLOCK : Azure Container Registry Access"
      block: |2
        secretGenerator:
          - name: sas-image-pull-secrets
            behavior: replace
            type: kubernetes.io/dockerconfigjson
            files:
              - .dockerconfigjson=site-config/cr/cr_azure_access.json
EOF
ansible-playbook ./azureCRSecrets.yml --diff



### NOT ON REDEPLOY...
mkdir -p /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/openldap/
cp -p /deployment_resources/viya4-deployment/examples/openldap/openldap-modify-users.yaml /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/openldap/openldap-modify-users.yaml

vi /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/openldap/openldap-modify-users.yaml
####
#
# MANUALLY EDIT THE USERS DETAILS IN
#    /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/openldap/openldap-modify-users.yaml
####

tee /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/openldap/openldap-modify-adminpassword.yaml > /dev/null << EOF
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: openldap-adminpassword
patch: |-
  - op: replace
    path: /data/LDAP_ADMIN_PASSWORD
    value: ${deployment_iac_viya4deployment_openldap_adminpassword}
target:
  kind: ConfigMap
  name: openldap-bootstrap-config
  version: v1
EOF

tee /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/sitedefault.yaml > /dev/null << EOF
cacerts:
config:
    application:
        sas.identities.providers.ldap.connection:
            host: ldap-svc
            password: ${deployment_iac_viya4deployment_openldap_adminpassword}
            port: 389
            userDN: cn=admin,dc=example,dc=com
        sas.identities.providers.ldap.group:
            baseDN: ou=groups,dc=example,dc=com
            accountId: cn
            member: uniqueMember
            memberOf: memberOf
            objectClass: groupOfUniqueNames
            objectFilter: (objectClass=groupOfUniqueNames)
            searchFilter: cn={0}
        sas.identities.providers.ldap.user:
            baseDN: ou=people,dc=example,dc=com
            accountId: uid
            memberOf: memberOf
            objectClass: inetOrgPerson
            objectFilter: (objectClass=inetOrgPerson)
            searchFilter: uid={0}
        sas.logon.initial.password: ${deployment_environment}admin
    identities:
        sas.identities:
            administrator: viya_admin
EOF


###################################################################
#
#    Create NAMESPACE
#
###################################################################
kubectl create ns ${deployment_environment}
kubectl config set-context --current --namespace=${deployment_environment}

###################################################################
#
#    Deploy Viya 4 in AKS
#
###################################################################
  
#######################
###   BUILD STEP    ###
#######################
cd /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/
kustomize build -o site.yaml

#######################
### DEPLOYMENT STEP ###
#######################

# Apply the "cluster wide" configuration in site.yaml (CRDs, Roles, Service Accounts)
kubectl apply --selector="sas.com/admin=cluster-wide" -f site.yaml

# Wait for Custom Resource Deployment to be deployed
kubectl wait --for condition=established --timeout=60s -l "sas.com/admin=cluster-wide" crd

#Apply the "cluster local" configuration in site.yaml and delete all the other "cluster local" resources that are not in the file (essentially config maps)
kubectl apply --selector="sas.com/admin=cluster-local" -f site.yaml --prune

# Apply the configuration in manifest.yaml that matches label "sas.com/admin=namespace" and delete all the other resources that are not in the file and match label "sas.com/admin=namespace".
kubectl apply --selector="sas.com/admin=namespace" -f site.yaml --prune
########################
##        WAIT       ###
########################
while true;
do
kubectl get pods -o wide -n proving1 | sed -n "1,56p"
sleep 2
kubectl get pods -o wide -n proving1 | sed -n '57,$p'
sleep 5
for i in sas-consul-server-0 sas-rabbitmq-server-0 sas-cachelocator-0 sas-cacheserver-0 sas-cas-server-default-controller;  do 
echo "POD: $i"
kubectl describe pods $i | tail -n5
done
sleep 10
echo ""
done

## ASSOCIATE DNS
kubectl get svc -n ingress-nginx
LBIP=$(kubectl get service -n ingress-nginx | grep LoadBalancer | awk '{print $4}')
echo $LBIP

# get the LB Public IP id (as defined in the Azure Cloud)
PublicIPId=$(az network lb show \
              -g MC_${deployment_name}-viya4aks-rg_${deployment_name}-viya4aks-aks_${deployment_iac_azure_location} \
              -n kubernetes \
              --query "frontendIpConfigurations[].publicIpAddress.id" \
               --out table | grep kubernetes\
               )
echo $PublicIPId

#use the Id to associate a DNS alias
az network public-ip update \
  -g MC_${deployment_name}-viya4aks-rg_${deployment_name}-viya4aks-aks_${deployment_iac_azure_location} \
  --ids $PublicIPId --dns-name ${deployment_environment}-${deployment_name}

#get the FQDN
FQDN=$(az network public-ip show --ids "${PublicIPId}" --query "{ fqdn: dnsSettings.fqdn }" --out tsv)
echo $FQDN
# curl it
curl $FQDN

## Sign in as SASBOOT
echo "Go To https://$FQDN/SASEnvironmentManager/"
echo "Use password: ${deployment_environment}admin"



## For the next time we want to start the Viya 4 containers, you can simply reapply the site.yaml file with the command below (since the components created outside of the namespace scope will already be there)
cd /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/
kubectl -n ${deployment_environment} apply -f site.yaml

kubectl config set-context --current --namespace=${deployment_environment}


## Scheduled Stop/Start

mkdir /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/site-config/admin
cd /deployment_resources/deployments/${deployment_name}-viya4aks-aks/${deployment_environment}/
cat > ./site-config/admin/scheduledStop.yaml << EOF
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: everyday-stop-all
patch: |-
  - op: replace
    path: /spec/schedule
    value: '0 8 * * *'
  - op: replace
    path: /spec/suspend
    value: false
target:
  name: sas-stop-all
  kind: CronJob
EOF

cat > ./site-config/admin/scheduledStart.yaml << EOF
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: weekdays-start-all
patch: |-
  - op: replace
    path: /spec/schedule
    value: '0 22 * * 1-5'
  - op: replace
    path: /spec/suspend
    value: false
target:
  name: sas-start-all
  kind: CronJob
EOF

vi kustomization.yaml



##


### EXIT BLOCK ###

## pid file management ##
rm $PIDFILE

