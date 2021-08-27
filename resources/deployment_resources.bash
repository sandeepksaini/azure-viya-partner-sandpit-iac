#!/bin/bash

#### Ubuntu Cloud Orchestration Shell setup ####

# Ensure that a permanent home location is setup
# Run this in your WSL Ubuntu terminal to setup the required client tools to administrate a deployment
#
# NOTE:: Best to check your network connections to the required endpoints (like coporate network through VPN) work correctly before starting.
# Known issues with VPN require some DNS gymnastics

############################
# PARAMETER CALCULATION
############################
EXEC_DIR=$(pwd);
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
############################
# pushd ~/_git_home/azure_viya_ca_env_iac/ubuntu_deployer/
# DEFAULT_CONFIG_FILE=ubuntu_deployer-variables.yaml
# eval $(parse_yaml $DEFAULT_CONFIG_FILE)
# popd
############################

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

if [ -z "$1" ]
	then
		echo "No argument supplied."
		# Source default configuration
		if [ -f $SCRIPT_DIR/$DEFAULT_CONFIG_FILE ]
		then
			eval $(parse_yaml $SCRIPT_DIR/$DEFAULT_CONFIG_FILE)
		else
			echo "The default $DEFAULT_CONFIG_FILE file is missing from the script directory."
			exit 1;
		fi
	else
		if [ -f $1 ]
		then
			eval $(parse_yaml $SCRIPT_DIR/$DEFAULT_CONFIG_FILE)
		else
			echo "Argument is not a file"
			exit 1;
		fi
fi



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


