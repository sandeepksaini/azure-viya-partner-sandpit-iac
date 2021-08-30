#!/bin/bash

#### Deployment Resources Configuration ####

# This script assumes that the pre-requisites met by the ubuntu_deployer-setup.sh script are satisfied
# High level tasks are:
# 1. Login and configure Azure CLI
# 2. Create a resource group for deployment resources
# 3. Create and connect to a Storage Account to hold the deployment artifacts (terraform plans, kustomize files etc)
# 4. Create and mirror an Azure container registry from the SAS order


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

DEFAULT_CONFIG_FILE=deployment_resources-variables.yaml

############################
# For manual testing you can run this and the function above in your shell to parse your variables yaml file
pushd ~/_git_home/azure_viya_ca_env_iac/resources/
eval $(parse_yaml $DEFAULT_CONFIG_FILE)
popd
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

# AZURE LOGIN
az login --use-device-code

# Set Location & Subscription
echo "[INFO] Setting default location to $deployment_azure_location"
az configure --defaults location=${deployment_azure_location}
az account set -s ${deployment_azure_subscription}

# Check for orchestration resource group
echo "[INFO] Looking for an existing orchestration Resource Group"
deployment_azure_resources_orchestrationresourcegroup_id=$(az group show --name ${deployment_azure_resources_orchestrationresourcegroup} | jq -r '.id')
if [ -z "$deployment_azure_resources_orchestrationresourcegroup_id" ]
    then
        echo "[INFO] \"${deployment_azure_resources_orchestrationresourcegroup}\" does not yet exist. We'll create it..."
        az group create --name ${deployment_azure_resources_orchestrationresourcegroup} --location ${deployment_azure_location} | jq -r '.id')
    else
        echo -e "[INFO] \"$deployment_azure_resources_orchestrationresourcegroup\" Resource Group already exists:\n       id:    $deployment_azure_resources_orchestrationresourcegroup_id"
fi

## Mount the deployment resources File Share
echo "[INFO] Looking for an existing Azure Storage Account"
deployment_azure_resources_storageaccount_id=$(az storage account show --name ${deployment_azure_resources_storageaccount} | jq -r '.id')
if [ -z "$deployment_azure_resources_storageaccount_id" ]
    then
        echo "[INFO] \"${deployment_azure_resources_storageaccount}\" does not yet exist. We'll create it..."
        deployment_azure_resources_storageaccount= az storage account create --name ${deployment_azure_resources_storageaccount} --resource-group $deployment_azure_resources_orchestrationresourcegroup
    else
        echo -e "[INFO] \"$deployment_azure_resources_storageaccount\" Resource Group already exists:\n       id:    $deployment_azure_resources_orchestrationresourcegroup_id"
fi

sudo mkdir /deployment_resources
sudo chown $LOGNAME /deployment_resources

httpEndpoint=$(az storage account show \
    --resource-group $deployment_azure_resources_orchestrationresourcegroup \
    --name $deployment_resources_storageaccount \
    --query "primaryEndpoints.file" | tr -d '"')
echo $httpEndpoint
deployment_deploymentresources_filesharesmbPath=$(echo $httpEndpoint | cut -c7-$(expr length $httpEndpoint))$deployment_deploymentresources_filesharename
echo $deployment_deploymentresources_filesharesmbPath
storageAccountKey=$(az storage account keys list \
    --resource-group $deployment_azure_resources_orchestrationresourcegroup \
    --account-name $deployment_resources_storageaccount \
    --query "[0].value" | tr -d '"')

# Save Creds & Set automount
echo "username=$deployment_resources_azurestorageaccount" | tee /home/viyadeployer/.azureStorageAccCreds > /dev/null
echo "password=$storageAccountKey" | tee -a /home/viyadeployer/.azureStorageAccCreds > /dev/null
sudo chmod 600 /home/viyadeployer/.azureStorageAccCreds
if [ -z "$(grep $deployment_deploymentresources_filesharesmbPath /etc/fstab)" ]; then
    echo "$deployment_deploymentresources_filesharesmbPath/ /deployment_resources cifs nofail,vers=3.0,credentials=/home/viyadeployer/.azureStorageAccCreds,serverino,uid=1000,gid=1000 0 0" | sudo tee -a /etc/fstab > /dev/null
else
    echo "/etc/fstab was not modified to avoid conflicting entries as this Azure file share was already present"
fi
sudo mount -a
## MANUAL MOUNT
#sudo mount -t cifs "$deployment_deploymentresources_filesharesmbPath/" /deployment_resources -o username=$deployment_resources_azurestorageaccount,password=$storageAccountKey,serverino,uid=1000,gid=1000


