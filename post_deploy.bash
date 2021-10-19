#!/bin/bash

#### Viya4 Post Deployment ####

# This script assumes you have a running viya4 environment setup with the scripts in this repo


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

# DEFAULT_CONFIG_FILE=post-deploy-variables.yaml

# ############################
# # pushd ~/_git_home/azure_viya_ca_env_iac/
# # DEFAULT_CONFIG_FILE=post-deploy-variables.yaml
# # eval $(parse_yaml $DEFAULT_CONFIG_FILE)
# # popd
# ############################

# if [ -z "$1" ]
    # then
        # echo "[INFO] No argument supplied; using the default"
        # # Source default configuration
        # if [ -f $SCRIPT_DIR/$DEFAULT_CONFIG_FILE ]
        # then
            # eval $(parse_yaml $SCRIPT_DIR/$DEFAULT_CONFIG_FILE)
        # else
            # echo "[ERROR] The default $DEFAULT_CONFIG_FILE file is missing from the script directory."
            # exit 1;
        # fi
    # else
        # if [ -f $1 ]
        # then
            # eval $(parse_yaml $SCRIPT_DIR/$DEFAULT_CONFIG_FILE)
        # else
            # echo "[ERROR] Argument is not a file"
            # exit 1;
        # fi
# fi


############################
## Scheduled Stop/Start
############################
echo "[INFO] Generate Start/Stop Transformers"
mkdir $HOME/${deployment_name}-aks/${deployment_environment}/site-config/admin
cd $HOME/${deployment_name}-aks/${deployment_environment}/
cat > ./site-config/admin/scheduledStop.yaml << EOF
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: sas-stop-all
patch: |-
  - op: replace
    path: /spec/schedule
    value: '0 7 * * *'
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
  name: sas-start-all
patch: |-
  - op: replace
    path: /spec/schedule
    value: '0 21 * * 0-4'
  - op: replace
    path: /spec/suspend
    value: false
target:
  name: sas-start-all
  kind: CronJob
EOF

echo "[INFO] Ansible task to add references in kustomization.yaml"
cat > ./addScheduledStartStop.yml << EOF
---
- hosts: localhost
  tasks:
  - name: Add scheduled start and stop transformers to kustomization.yaml
    blockinfile:
      path: $HOME/${deployment_name}-aks/${deployment_environment}/kustomization.yaml
      insertafter: "  - site-config/vdm/transformers/sas-storageclass.yaml"
      marker: "  # {mark} ANSIBLE MANAGED BLOCK : scheduled start and stop"
      block: |2
          - site-config/admin/scheduledStart.yaml
          - site-config/admin/scheduledStop.yaml
EOF
## Run that
ansible-playbook ./addScheduledStartStop.yml --diff


echo "[INFO] Rebuild site.yaml from all kustomizations"
kustomize build -o site.yaml
echo "[INFO] Apply to the environment"
kubectl -n ${deployment_environment} apply -f site.yaml

kubectl get cronjobs;

echo "[INFO] Check that the start and stop jobs above are no longer suspended and have the updated schedule"
echo "[INFO] All resources are deployed in UTC by default."
