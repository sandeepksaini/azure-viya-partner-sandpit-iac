#!/bin/bash

#### Viya4 Deployment - SOURCING SCRIPT ####

# This script is simply to parse all the variables files so the environment variables are available to you.


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

if [ -f $SCRIPT_DIR/core-variables.yaml ]
then
    echo "[INFO] Setting core-variables"
    eval $(parse_yaml $SCRIPT_DIR/core-variables.yaml)
else
    echo "[ERROR] no core-variables.yaml file in the parent directory"
    exit 1;
fi

if [ -f $SCRIPT_DIR/ubuntu_deployer/ubuntu_deployer-variables.yaml ]
then
    echo "[INFO] Setting ubuntu_deployer-variables "
    eval $(parse_yaml $SCRIPT_DIR/ubuntu_deployer/ubuntu_deployer-variables.yaml)
else
    echo "[ERROR] no ubuntu_deployer-variables.yaml file in the expected path!"
    exit 1;
fi


if [ -f $SCRIPT_DIR/resources/deployment_repo-variables.yaml ]
then
    echo "[INFO] Setting deployment_repo-variables "
    eval $(parse_yaml $SCRIPT_DIR/resources/deployment_repo-variables.yaml)
else
    echo "[ERROR] no deployment_repo-variables.yaml file in the expected path!"
    exit 1;
fi

if [ -f $SCRIPT_DIR/iac/iac_build-variables.yaml ]
then
    echo "[INFO] Setting deployment_repo-variables "
    eval $(parse_yaml $SCRIPT_DIR/iac/iac_build-variables.yaml)
else
    echo "[ERROR] no iac_build-variables.yaml file in the expected path!"
    exit 1;
fi

if [ -f $SCRIPT_DIR/viya/viya-deployment-variables.yaml ]
then
    echo "[INFO] Setting viya-deployment-variables "
    eval $(parse_yaml $SCRIPT_DIR/viya/viya-deployment-variables.yaml)
else
    echo "[ERROR] no viya-deployment-variables.yaml file in the expected path!"
    exit 1;
fi