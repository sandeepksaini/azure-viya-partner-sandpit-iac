#!/bin/bash

#### Ubuntu Cloud Orchestration Shell setup ####

# Ensure that a permanent home location is setup
# Run this in your WSL Ubuntu terminal to setup the required client tools to administrate a deployment

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

DEFAULT_CONFIG_FILE=ubuntu_deployer-variables.yaml

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

# python & pip setup
pip3 install --upgrade pip

# Add $HOME/.local/bin/ to PATH, required for some clients
[[ ":$PATH:" != *":HOME/.local/bin/:"* ]] && PATH="HOME/.local/bin/:${PATH}"

# CLI Installs
echo "[INFO] installing azure-cli ${client_azurecli_version}..."
pip3 install azure-cli==${client_azurecli_version}

echo "[INFO] installing ansible $client_ansible_version..."
pip3 install ansible==${client_ansible_version}

echo "[INFO] installing terraform $client_terraform_version..."
mkdir -p /usr/bin
cd /usr/bin
sudo rm -Rf /usr/bin/terraform
sudo curl -o terraform.zip -s https://releases.hashicorp.com/terraform/${client_terraform_version}/terraform_${client_terraform_version}_linux_amd64.zip
sudo unzip terraform.zip && sudo rm -f terraform.zip
export PATH=$PATH:/usr/bin
/usr/bin/terraform version

echo "[INFO] installing yq $client_yq_version..."
sudo wget https://github.com/mikefarah/yq/releases/download/${client_yq_version}/${client_yq_binary} -O /usr/bin/yq &&\
    sudo chmod +x /usr/bin/yq
/usr/bin/yq --version

echo "[INFO] installing Helm From the Binary Release version ${client_helm_version} for ${client_helm_binary}"
echo "[INFO]     ... for available versions see https://github.com/helm/helm/releases"
cd ~/
#https://get.helm.sh/helm-v3.6.3-linux-amd64.tar.gz
sudo wget https://get.helm.sh/helm-v${client_helm_version}-${client_helm_binary}.tar.gz -O helm-v${client_helm_version}-${client_helm_binary}.tar.gz
tar -zxvf helm-v${client_helm_version}-${client_helm_binary}.tar.gz && \
sudo mv ${client_helm_binary}/helm /usr/bin/ && \
sudo rm -f helm-v${client_helm_version}-${client_helm_binary}.tar.gz && \
sudo rm -rf ${client_helm_binary}
/usr/bin/helm version

## Package managed version is community supported. Binaries are better
# sudo apt-get install apt-transport-https --yes
# echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
# sudo apt-get update
# sudo apt-get install helm


echo "[INFO] installing kubectl $client_kubectl_version..."
sudo curl -LO "https://dl.k8s.io/release/v${client_kubectl_version}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/bin/kubectl &&\
rm -f kubectl

# python & pip setup
ansible localhost -m lineinfile -a "dest=~/.bashrc line='alias python=python3'" --diff
ansible localhost -m lineinfile -a "dest=~/.bashrc line='alias pip=pip3'" --diff

cd $EXEC_DIR
