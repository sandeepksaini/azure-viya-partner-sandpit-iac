#!/bin/bash

#### Deployment Resources Repository Configuration ####

# This script assumes that the pre-requisites met by the ubuntu_deployer-setup.sh script are satisfied
# High level tasks are:
# 1. Login and configure Azure CLI
# 2. Create a git repository for this artifacts for managing this deployment
# 3. Populate the git repo with base deployment artifacts using repo pull, order download CLIs etc
# 4. Create and mirror an Azure container registry from the SAS order

# At the completion of this step your setup should be ready to customize the deployment


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

DEFAULT_CONFIG_FILE=deployment_repo-variables.yaml

############################
# For manual testing you can run this and the function above in your shell to parse your variables yaml file
# 
# DEFAULT_CONFIG_FILE=deployment_repo-variables.yaml
# pushd ~/_git_home/azure_viya_ca_env_iac/resources/
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


# Configure GIT
echo "[INFO] Configuring git client."
git config --global user.name ${deployment_git_user_name}
git config --global user.email ${deployment_git_user_email}

# Create an SSH key for use with Gitlab/Github AND the deployment
echo "[INFO] Generate SSH key for this deployment (git authorisation and deployment resource access)"
tee $HOME/gen_ssh.yaml > /dev/null << EOF
---
- hosts: localhost
  tasks:
  - name: Generate an OpenSSH keypair with the deployment_git_user values
    community.crypto.openssh_keypair:
      type: rsa
      path: $HOME/.ssh/${deployment_name}_id_rsa
      comment: ${deployment_git_user_name} @ ${deployment_git_gitbase}${deployment_name}
      force: false
EOF

ansible-playbook gen_ssh.yaml

echo -e "[IMPORTANT] THIS SSH KEY HAS FULL ACCESS TO THE WHOLE DEPLOYMENT. GUARD IT WELL. \n    $HOME/.ssh/${deployment_name}_id_rsa.pub"

echo "Your SSH public key needs to be added to Gitlab to maintain the deployment configuration there.
Please copy the below text and add to to your profile in Gilab:

$(cat $HOME/.ssh/${deployment_name}_id_rsa.pub)

"

############################
# Deployment resources setup locations
## !! IMPORTANT CONCEPT !! ##
# deployment_name = the label for the infra deployment this deployment will run on
# deployment_environment = the label for this software deployment
############################
## CHECK IF THE git exists at the specified version first!!!
echo "[INFO] Generate SSH key for this deployment (git authorisation and deployment resource access)"
#### INITIAL SETUP ####
if [ -f $HOME/${deployment_name}-aks ]
then
    cd $HOME/${deployment_name}-aks
else
    mkdir -p $HOME/${deployment_name}-aks
fi

# Clone SAS Viya IAC git
echo "[INFO] Clone SAS Viya IAC Azure git repo"
cd $HOME/${deployment_name}-aks
git clone https://github.com/sassoftware/viya4-iac-azure.git

# Instead of being at the mercy of the latest changes, we pin to a specific version
cd viya4-iac-azure
git fetch --all
git checkout tags/${deployment_viya4_iacazure_tag}


# Clone SAS Viya Deployment git
echo "[INFO] Clone SAS Viya 4 Deployment git repo"
cd $HOME/${deployment_name}-aks
git clone https://github.com/sassoftware/viya4-deployment.git
cd viya4-deployment
# Instead of being at the mercy of the latest changes, we pin to a specific version
git fetch --all
git checkout tags/${deployment_viya4_viya4deployment_versiontag}


############################
# AZURE CREDENTIALS
############################
echo "[PROMPT] Login to Azure..."
az login --use-device-code

# Set Location & Subscription
echo "[INFO] Setting default location to $deployment_azure_location"
az configure --defaults location=${deployment_azure_location}
echo "[INFO] Setting default subscription to $deployment_azure_subscription"
az account set -s ${deployment_azure_subscription}

# Create an Azure Service Principal for Terraform
echo "[INFO] Create an Azure Service Principal for Terraform."
TFCREDFILE=$HOME/${deployment_name}-aks/TF_CLIENT_CREDS
if [ ! -f "$TFCREDFILE" ]; then
SP_PASSWD=$(az ad sp create-for-rbac --skip-assignment --name ${deployment_name} --query password --output tsv)
SP_APPID=$(az ad sp list --display-name "${deployment_name}" | jq -r '.[].appId')
# give the "Contributor" role to your Azure SP
# You only have to do it once !
echo "[INFO] ... Assigning Contributor role"
az role assignment create --assignee $SP_APPID --role Contributor

# export the required values in TF required environment variables 
export TF_VAR_subscription_id=$(az account list --query "[?name=='$deployment_azure_subscription'].{id:id}" -o tsv)
export TF_VAR_tenant_id=$(az account list --query "[?name=='$deployment_azure_subscription'].{tenantId:tenantId}" -o tsv)
export TF_VAR_client_id=${SP_APPID}
export TF_VAR_client_secret=${SP_PASSWD}
  
printf "TF_VAR_subscription_id   -->   ${TF_VAR_subscription_id}
TF_VAR_tenant_id         -->   ${TF_VAR_tenant_id}
TF_VAR_client_id      -->   ${TF_VAR_client_id}
TF_VAR_client_secret  -->   ${TF_VAR_client_secret}\n"

# save the TF environment variables value for the next time
tee $HOME/${deployment_name}-aks/TF_CLIENT_CREDS > /dev/null << EOF
export TF_VAR_subscription_id=${TF_VAR_subscription_id}
export TF_VAR_tenant_id=${TF_VAR_tenant_id}
export TF_VAR_client_id=${TF_VAR_client_id}
export TF_VAR_client_secret=${TF_VAR_client_secret}
EOF

chmod u+x $HOME/${deployment_name}-aks/TF_CLIENT_CREDS
chmod o-rwx $HOME/${deployment_name}-aks/TF_CLIENT_CREDS
. $HOME/${deployment_name}-aks/TF_CLIENT_CREDS

# Force TF_CLIENT_CREDS to run next time we re-login
echo "[INFO] Setting Terraform environment variables sourcing at login."
ansible localhost -m lineinfile -a "dest=$HOME/.bashrc line='source $HOME/${deployment_name}-aks/TF_CLIENT_CREDS'" --diff
echo "[INFO] To use different Terraform credentials for a different environment, comment and uncomment $HOME/.bashrc as required."
fi

############################
# Download Order
############################
# License and Certificates (order scoped)
echo "[INFO] Downloading Order license and certificates"
mkdir -p $HOME/${deployment_name}-aks/orders/${deployment_viya4_ordernumber}/
pushd $HOME/${deployment_name}-aks/orders/${deployment_viya4_ordernumber}/
viya4-orders-cli certificates ${deployment_viya4_ordernumber}
viya4-orders-cli license ${deployment_viya4_ordernumber} ${deployment_viya4_cadencename} ${deployment_viya4_cadenceversion}

# Dynamically resolved variable now! (At parse time! How cool!)
# Set path variables
#deployment_viya4_certpath=$(readlink -f $HOME/${deployment_name}-aks/orders/${deployment_viya4_ordernumber}/*${deployment_viya4_ordernumber}_certs.zip)
#deployment_viya4_licensepath=$(readlink -f $HOME/${deployment_name}-aks/orders/${deployment_viya4_ordernumber}/*${deployment_viya4_ordernumber}_${deployment_viya4_cadencename}_${deployment_viya4_cadenceversion}_license*.jwt)


# Deployment Assets (cadence-version scoped)
echo "[INFO] Downloading Order Deployment Assets"
mkdir -p $HOME/${deployment_name}-aks/orders/${deployment_viya4_ordernumber}/${deployment_viya4_cadencename}/${deployment_viya4_cadenceversion}
cd $HOME/${deployment_name}-aks/orders/${deployment_viya4_ordernumber}/${deployment_viya4_cadencename}/${deployment_viya4_cadenceversion}
viya4-orders-cli deploymentAssets ${deployment_viya4_ordernumber} ${deployment_viya4_cadencename} ${deployment_viya4_cadenceversion}

# Dynamically resolved variable now! (At parse time! How cool!)
# Set path variables
#deployment_viya4_assetspath=$(ls -1 $HOME/${deployment_name}-aks/orders/${deployment_viya4_ordernumber}/${deployment_viya4_cadencename}/${deployment_viya4_cadenceversion}/SASViyaV4_${deployment_viya4_ordernumber}_${deployment_viya4_cadencename}_${deployment_viya4_cadenceversion}*.tgz | tail -n1)
