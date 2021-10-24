#!/bin/bash

#### IAC Build ####

# This script assumes you have the deployer environment setup (ubuntu_deployer-setup.sh) and the initial deployment configuration path is setup either initially (deployment-repo-setup.bash), or from a git pull


############################
# PARAMETER CALCULATION
############################
EXEC_DIR=$(pwd);
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)


###########################################################################################################
### FUNCTION BLOCK ###
###########################################################################################################

## https://gist.github.com/masukomi/e587aa6fd4f042496871
# Here is a bash-only YAML parser that leverages sed and awk to parse simple yaml files.
# typical use within a script is:   eval $(parse_yaml sample.yml)
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
###########################################################################################################
###########################################################################################################

if [ -f $SCRIPT_DIR/../core-variables.yaml ]
then
    echo "[INFO] Setting core-variables"
    eval $(parse_yaml $SCRIPT_DIR/../core-variables.yaml)
else
    echo "[ERROR] no core-variables.yaml file in the parent directory"
    exit 1;
fi

if [ -f $SCRIPT_DIR/../resources/deployment_repo-variables.yaml ]
then
    echo "[INFO] Setting pre-requisite deployment_repo-variables "
    eval $(parse_yaml $SCRIPT_DIR/../resources/deployment_repo-variables.yaml)
else
    echo "[ERROR] no deployment_repo-variables.yaml file in the expected path!"
    exit 1;
fi

DEFAULT_CONFIG_FILE=iac_build-variables.yaml

############################
# pushd ~/_git_home/azure_viya_ca_env_iac/iac/
# DEFAULT_CONFIG_FILE=iac_build-variables.yaml
# eval $(parse_yaml $DEFAULT_CONFIG_FILE)
# popd
############################

if [ -z "$1" ]
	then
		echo "[INFO] No argument supplied; using the default"
		# Source default configuration
		if [ -f $SCRIPT_DIR/$DEFAULT_CONFIG_FILE ]
		then
			eval $(parse_yaml $SCRIPT_DIR/$DEFAULT_CONFIG_FILE)
		else
			echo "[ERROR] The default $DEFAULT_CONFIG_FILE file is missing from the script directory."
			exit 1;
		fi
	else
		if [ -f $1 ]
		then
			eval $(parse_yaml $SCRIPT_DIR/$DEFAULT_CONFIG_FILE)
		else
			echo "[ERROR] Argument is not a file"
			exit 1;
		fi
fi

source $HOME/pyvenv_${deployment_name}/bin/activate

## SITE CONFIG
echo "[INFO] Copy license to site-config (this is a workaround)"
mkdir -p $HOME/${deployment_name}-aks/${deployment_environment}/site-config
cp -p ${deployment_viya4_licensepath} $HOME/${deployment_name}-aks/${deployment_environment}/site-config/license.jwt

# Initialize Terraform
echo "[INFO] Initialize Terraform."
cd $HOME/${deployment_name}-aks/viya4-iac-azure
terraform init

# get azure user email address for tagging
az ad signed-in-user show --query userPrincipalName \
| sed  's|["\ ]||g' \
| tee ~/.email.txt
# store email address in a variable to use later in TF variable
EMAIL=$(cat ~/.email.txt)

# Populate the TF variables file
echo "[INFO] Populate the TF variables file."
echo "[REF] https://github.com/sassoftware/viya4-iac-azure/blob/main/docs/CONFIG-VARS.md"

tee $HOME/${deployment_name}-aks/viya4-iac-azure/$deployment_name.tfvars > /dev/null << EOF
#### REQUIRED VARIABLES ####
prefix                               = "${deployment_name}"
location                             = "${deployment_azure_location}"
ssh_public_key                       = "$HOME/.ssh/${deployment_name}_id_rsa.pub"

#### General config ####
kubernetes_version                   = "${deployment_iac_kubernetes_version}"
# no jump host machine
create_jump_vm                       = "false"
create_jump_public_ip                = "false"
# tags in azure
tags                                 = { "resourceowner" = "${EMAIL}" , project_name = "${deployment_name}", environment = "${deployment_environment}" }

#### Azure Auth ####
# not required if already set in TF environment variables?
# tenant_id                            = ${TF_VAR_tenant_id}
# subscription_id                      = ${TF_VAR_subscription_id}
# client_id                            = ${TF_VAR_client_id}
# client_secret                        = ${TF_VAR_client_secret}

#### Admin Access ####
# IP Ranges allowed to access all created cloud resources
default_public_access_cidrs         = ${deployment_iac_network_defaultpublicaccesscidrs}

#### Storage ####
# "dev" creates AzureFile, "standard" creates NFS server VM, "ha" creates Azure Netapp Files
storage_type                         = "standard"
create_nfs_public_ip                 = "${deployment_iac_storage_nfs_publicip}"
nfs_vm_admin                         = "${deployment_iac_storage_nfs_adminuser}"
nfs_vm_machine_type                  = "${deployment_iac_storage_nfs_vm_machinetype}"
nfs_vm_zone                          = "${deployment_iac_storage_nfs_vm_zone}"
nfs_raid_disk_type                   = "${deployment_iac_storage_nfs_raid_disktype}"
nfs_raid_disk_size                   = "${deployment_iac_storage_nfs_raid_disksize}"
nfs_raid_disk_zones                  = ${deployment_iac_storage_nfs_raid_diskzones}
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
        "machine_type" = "${deployment_iac_nodepools_cas_machinetype}"
        "os_disk_size" = "${deployment_iac_nodepools_cas_osdisksize}"
        "min_nodes" = "${deployment_iac_nodepools_cas_minnodes}"
        "max_nodes" = "${deployment_iac_nodepools_cas_maxnodes}"
        "max_pods" = "${deployment_iac_nodepools_cas_maxpods}"
        "node_taints" = ["workload.sas.com/class=cas:NoSchedule"]
        "node_labels" = {
            "workload.sas.com/class" = "cas"
        }
    },
    compute = {
        "machine_type" = "${deployment_iac_nodepools_compute_machinetype}"
        "os_disk_size" = "${deployment_iac_nodepools_compute_osdisksize}"
        "min_nodes" = "${deployment_iac_nodepools_compute_minnodes}"
        "max_nodes" = "${deployment_iac_nodepools_compute_maxnodes}"
        "max_pods" = "${deployment_iac_nodepools_compute_maxpods}"
        "node_taints" = ["workload.sas.com/class=compute:NoSchedule"]
        "node_labels" = {
            "workload.sas.com/class"        = "compute"
            "launcher.sas.com/prepullImage" = "sas-programming-environment"
        }
    },
    connect = {
        "machine_type" = "${deployment_iac_nodepools_connect_machinetype}"
        "os_disk_size" = "${deployment_iac_nodepools_connect_osdisksize}"
        "min_nodes" = "${deployment_iac_nodepools_connect_minnodes}"
        "max_nodes" = "${deployment_iac_nodepools_connect_maxnodes}"
        "max_pods" = "${deployment_iac_nodepools_connect_maxpods}"
        "node_taints" = ["workload.sas.com/class=connect:NoSchedule"]
        "node_labels" = {
            "workload.sas.com/class"        = "connect"
            "launcher.sas.com/prepullImage" = "sas-programming-environment"
        }
    },
    stateless = {
        "machine_type" = "${deployment_iac_nodepools_stateless_machinetype}"
        "os_disk_size" = "${deployment_iac_nodepools_stateless_osdisksize}"
        "min_nodes" = "${deployment_iac_nodepools_stateless_minnodes}"
        "max_nodes" = "${deployment_iac_nodepools_stateless_maxnodes}"
        "max_pods" = "${deployment_iac_nodepools_stateless_maxpods}"
        "node_taints" = ["workload.sas.com/class=stateless:NoSchedule"]
        "node_labels" = {
            "workload.sas.com/class" = "stateless"
        }
    },
    stateful = {
        "machine_type" = "${deployment_iac_nodepools_stateful_machinetype}"
        "os_disk_size" = "${deployment_iac_nodepools_stateful_osdisksize}"
        "min_nodes" = "${deployment_iac_nodepools_stateful_minnodes}"
        "max_nodes" = "${deployment_iac_nodepools_stateful_maxnodes}"
        "max_pods" = "${deployment_iac_nodepools_stateful_maxpods}"
        "node_taints" = ["workload.sas.com/class=stateful:NoSchedule"]
        "node_labels" = {
            "workload.sas.com/class" = "stateful"
        }
    }
}

EOF

# Adjustment to add the required paths for the nfs-clients to connect
echo "[INFO] Workaround to add the required paths for the nfs-clients to connect."
cat > ./addNFSstructure.yml << EOF
---
- hosts: localhost
  tasks:
  - name: Create NFS folder structure config
    blockinfile:
      path: $HOME/${deployment_name}-aks/viya4-iac-azure/files/cloud-init/nfs/cloud-config
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

#####################################################################################
# Generate the TF plan corresponding to the AKS cluster with multiple node pools ####
#####################################################################################
echo "[INFO] Generate the TF plan corresponding to the AKS cluster with multiple node pools."
cd $HOME/${deployment_name}-aks/viya4-iac-azure
terraform plan -input=false \
    -var-file=./$deployment_name.tfvars \
    -out ./$deployment_name-aks.plan

##################################################
##### Deploy the AKS cluster with the TF plan ####
##################################################
echo "[INFO] Deploy the AKS cluster with the TF plan."
cd $HOME/${deployment_name}-aks/viya4-iac-azure
TFPLAN=$deployment_name-aks.plan
#terraform show ${TFPLAN}
time terraform apply "./${TFPLAN}" 2>&1 \
| tee -a $HOME/${deployment_name}-aks/viya4-iac-azure/$(date +%Y%m%dT%H%M%S)_terraform-apply.log
##################################################

# Generate the config file with a recognizable name
echo "[INFO] Generate the kube_config file with a recognizable name."
mkdir -p ~/.kube
terraform output kube_config | sed '1d;$d' > ~/.kube/${deployment_name}-aks-kubeconfig.conf

echo "[INFO] Sym-link the kubeconfig."
SOURCEFILE=~/.kube/${deployment_name}-aks-kubeconfig.conf
ansible localhost -m file \
  -a "src=$SOURCEFILE \
      dest=~/.kube/config state=link" \
  --diff

# Set the kubeconfig directory
echo "[INFO] Source kube_config on login."
echo "[INFO] To use different kube_config credentials for a different environment, delete the existing ~/.kube/config sym-link and create a new link to the correct kube_config file for your target environment."
export KUBECONFIG=~/.kube/config
ansible localhost \
    -m lineinfile \
    -a "dest=~/.bashrc \
        line='export KUBECONFIG=~/.kube/config' \
        state=present" \
    --diff
	
# Configure kubectl auto-completion
echo "[INFO] Setup kubectl auto-completion."
source <(kubectl completion bash)
ansible localhost \
    -m lineinfile \
    -a "dest=~/.bashrc \
        line='source <(kubectl completion bash)' \
        state=present" \
    --diff

# Disable the authorized IP range for the Kubernetes API
echo "[INFO] Disable the authorized IP range for the Kubernetes API."
az aks update -n ${deployment_name}-aks \
    -g ${deployment_name}-rg --api-server-authorized-ip-ranges ""

# See nodes created
echo "[INFO] Check that nodes are starting..."
kubectl get nodes

# See nodes created
echo "[INFO] Once the infrastructure is all running, you can proceed to the viya4 deployment."
