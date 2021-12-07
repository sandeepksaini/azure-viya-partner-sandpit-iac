#!/bin/bash

#### Viya4 Deployment ####

# This script assumes you have the deployer environment setup (ubuntu_deployer-setup.sh)
# and the initial deployment configuration path is setup either initially (deployment-repo-setup.bash), or from a git pull
# and there is an IAC deployment 


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

DEFAULT_CONFIG_FILE=viya-deployment-variables.yaml

############################
# pushd ~/_git_home/azure_viya_ca_env_iac/viya/
# DEFAULT_CONFIG_FILE=viya-deployment-variables.yaml
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

# Ensure the environment is sourced as expected
source $HOME/pyvenv_${deployment_name}/bin/activate
source $HOME/${deployment_name}-aks/TF_CLIENT_CREDS

echo "[INFO] Environment folder setup"
#### INITIAL SETUP ####
## CHECK IF THE environment folder exists
if [ -f $HOME/${deployment_name}-aks/${deployment_environment}  ]
then
    cd $HOME/${deployment_name}-aks/${deployment_environment} 
else
    mkdir -p $HOME/${deployment_name}-aks/${deployment_environment}
    cd $HOME/${deployment_name}-aks/${deployment_environment} 
fi
 
# deployment_viya4_certpath=$(readlink -f $HOME/${deployment_name}-aks/orders/${deployment_viya4_ordernumber}/*${deployment_viya4_ordernumber}_certs.zip)

# deployment_viya4_licensepath=$(readlink -f $HOME/${deployment_name}-aks/orders/${deployment_viya4_ordernumber}/*${deployment_viya4_ordernumber}_${deployment_viya4_cadencename}_${deployment_viya4_cadenceversion}_license*.jwt)

# deployment_viya4_assetspath=$(ls -1 $HOME/${deployment_name}-aks/orders/${deployment_viya4_ordernumber}/${deployment_viya4_cadencename}/${deployment_viya4_cadenceversion}/SASViyaV4_${deployment_viya4_ordernumber}_${deployment_viya4_cadencename}_${deployment_viya4_cadenceversion}*.tgz | tail -n1)


echo "[INFO] viya4-deployment IAC manifest generation"
echo "[REF] https://github.com/sassoftware/viya4-deployment/blob/main/examples/ansible-vars-iac.yaml"
# viya4-deployment IAC Manifest
tee $HOME/${deployment_name}-aks/${deployment_environment}/ansible-vars-iac_manifests.yaml > /dev/null << EOF
## Cluster
NAMESPACE: ${deployment_environment}

## MISC
DEPLOY: false # Set to false to stop at generating the manifest
LOADBALANCER_SOURCE_RANGES: ${deployment_environment_ingress_sourceranges}

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

## Ingress
V4_CFG_INGRESS_TYPE: ingress
V4_CFG_INGRESS_FQDN: "${deployment_environment}-${deployment_name}.${deployment_azure_location}.cloudapp.azure.com"
V4_CFG_TLS_MODE: "front-door" # [full-stack|front-door|disabled]

## Postgres
V4_CFG_POSTGRES_TYPE: internal #[internal|external]

## LDAP
V4_CFG_EMBEDDED_LDAP_ENABLE: true

## Consul UI
V4_CFG_CONSUL_ENABLE_LOADBALANCER: false

## SAS/CONNECT
V4_CFG_CONNECT_ENABLE_LOADBALANCER: false

V4_CFG_POSTGRES_SERVERS:
  default:
    internal: true
    server_port: 5432
    database: SharedServices
  otherdb:
    internal: true
    admin: ${deployment_environment_secondpostgres_adminlogin}
    password: "${deployment_environment_secondpostgres_adminpassword}"
    database: OtherDB

## Monitoring and Logging
## uncomment and update the below values when deploying the viya4-monitoring-kubernetes stack
#V4M_BASE_DOMAIN: adm

## Enable opendistro elasticsearch
V4_CFG_ELASTICSEARCH_ENABLE: true

EOF


cd $HOME/${deployment_name}-aks/viya4-deployment/

# Update the requirements files to align with your versions (this actually just sucks, comment ou tansible, it's already installed)
# sed -i.bak -re 's/ansible==.*/ansible=='"$(ansible --version | grep -P "ansible [\d\.]+" | sed -re 's/ansible (.*)/\1/')"'/' requirements.txt
## THIS COULD BREAK EVERYTHING ##

# Active your virtualenv
source $HOME/pyvenv_${deployment_name}/bin/activate

# install python packages
echo "[INFO] Satisfy python requirements for viya4-deployment"
pip3 install -r requirements.txt

# install ansible collections
ansible-galaxy collection install -r requirements.yaml -f

### OPENLDAP SETUP ###
echo "[INFO] OpenLDAP modify users to suit the environment..."
mkdir -p $HOME/${deployment_name}-aks/${deployment_environment}/site-config/openldap/

firstname=$(echo ${deployment_git_user_email} | sed -re 's/([A-z-]+)\.([A-z-]+)@sas\.com/\1/')
lastname=$(echo ${deployment_git_user_email} | sed -re 's/([A-z-]+)\.([A-z-]+)@sas\.com/\2/')
sed -r -e "s/basic_user1@example.com/${deployment_git_user_email}/g" \
-e "s/basic_user1/${deployment_git_user_name}/g" \
-e "s/mySuperSecretPassword/${deployment_environment_openldap_viyaadminspassword}/g" \
-e "s/Password123/${deployment_environment_openldap_viyaadminspassword}/g" \
-e "s/Basic User 1/${firstname} ${lastname}/g" \
-e "s/BasicUser/${lastname}/g" $HOME/${deployment_name}-aks/viya4-deployment/examples/openldap/openldap-modify-users.yaml > $HOME/${deployment_name}-aks/${deployment_environment}/site-config/openldap/openldap-modify-users.yaml

####
#
# EDIT THE USERS DETAILS IN
#    $HOME/${deployment_name}-aks/${deployment_environment}/site-config/openldap/openldap-modify-users.yaml
####

tee $HOME/${deployment_name}-aks/${deployment_environment}/site-config/openldap/openldap-modify-adminpassword.yaml > /dev/null << EOF
---
apiVersion: builtin
kind: PatchTransformer
metadata:
  name: openldap-adminpassword
patch: |-
  - op: replace
    path: /data/LDAP_ADMIN_PASSWORD
    value: ${deployment_environment_openldap_ldappassword}
target:
  kind: ConfigMap
  name: openldap-bootstrap-config
  version: v1
EOF

tee $HOME/${deployment_name}-aks/${deployment_environment}/site-config/sitedefault.yaml > /dev/null << EOF
cacerts:
config:
    application:
        sas.identities.providers.ldap.connection:
            host: ldap-svc
            password: ${deployment_environment_openldap_ldappassword}
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
        sas.logon.initial.password: ${deployment_environment_openldap_viyaadminspassword}
    identities:
        sas.identities:
            administrator: viya_admin
EOF



echo "[INFO] Generate and Install basline"
ansible-playbook \
  -e BASE_DIR=$HOME \
  -e CONFIG=$HOME/${deployment_name}-aks/${deployment_environment}/ansible-vars-iac_manifests.yaml \
  -e TFSTATE=$HOME/${deployment_name}-aks/viya4-iac-azure/terraform.tfstate \
  -e ansible_python_interpreter=$HOME/pyvenv_${deployment_name}/bin/python \
  playbooks/playbook.yaml --tags "baseline,install"

# Gather required files, then generate Baseline & Viya deployment manifests
echo "[INFO] Generate but do not deploy the kustomize template for Viya 4 deployment"
ansible-playbook \
  -e BASE_DIR=$HOME \
  -e CONFIG=$HOME/${deployment_name}-aks/${deployment_environment}/ansible-vars-iac_manifests.yaml \
  -e TFSTATE=$HOME/${deployment_name}-aks/viya4-iac-azure/terraform.tfstate \
  -e ansible_python_interpreter=$HOME/pyvenv_${deployment_name}/bin/python \
  playbooks/playbook.yaml --tags "viya,install"

echo "[INFO] Add the pgAdmin pod overlay for access to the PostgreSQL servers"
ansible localhost \
    -m lineinfile \
    -a "dest=$HOME/${deployment_name}-aks/${deployment_environment}/kustomization.yaml \
        line='  - sas-bases/overlays/crunchydata_pgadmin' \
        state=present \
        insertafter='^  - sas-bases/overlays/cas-server/auto-resources$'" \
    --diff

###################################################################
#
#    Create NAMESPACE
#
###################################################################
echo "[INFO] Create kubernetes ${deployment_environment} namespace ..."
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
echo "[INFO] Run kustomize to build deployment site.yaml from our kustomizations..."
cd $HOME/${deployment_name}-aks/${deployment_environment}/
kustomize build -o site.yaml

#######################
### DEPLOYMENT STEP ###
#######################
echo "[INFO] BEGIN DEPLOYMENT..."
# Apply the "cluster wide" configuration in site.yaml (CRDs, Roles, Service Accounts)
kubectl apply --selector="sas.com/admin=cluster-wide" -f site.yaml

# Wait for Custom Resource Deployment to be deployed
kubectl wait --for condition=established --timeout=60s -l "sas.com/admin=cluster-wide" crd

#Apply the "cluster local" configuration in site.yaml and delete all the other "cluster local" resources that are not in the file (essentially config maps)
kubectl apply --selector="sas.com/admin=cluster-local" -f site.yaml --prune

# Apply the configuration in manifest.yaml that matches label "sas.com/admin=namespace" and delete all the other resources that are not in the file and match label "sas.com/admin=namespace".
kubectl apply --selector="sas.com/admin=namespace" -f site.yaml --prune

## ASSOCIATE DNS
kubectl get svc -n ingress-nginx
LBIP=$(kubectl get service -n ingress-nginx | grep LoadBalancer | awk '{print $4}')
echo $LBIP

# get the LB Public IP id (as defined in the Azure Cloud)
PublicIPId=$(az network lb show \
              -g MC_${deployment_name}-rg_${deployment_name}-aks_${deployment_azure_location} \
              -n kubernetes \
              --query "frontendIpConfigurations[].publicIpAddress.id" \
               --out table | grep kubernetes\
               )
echo $PublicIPId

#use the Id to associate a DNS alias
az network public-ip update \
  -g MC_${deployment_name}-viya4aks-rg_${deployment_name}-viya4aks-aks_${deployment_azure_location} \
  --ids $PublicIPId --dns-name ${deployment_environment}-${deployment_name}

#get the FQDN
FQDN=$(az network public-ip show --ids "${PublicIPId}" --query "{ fqdn: dnsSettings.fqdn }" --out tsv)
#echo $FQDN
# curl it
curl $FQDN

## Sign in as SASBOOT
echo "Go To https://$FQDN/SASEnvironmentManager/"
echo "Sign in as sasboot, viya_admin (the Viya Administrator account) or your own basic user account ${deployment_git_user_name},\n Use password:\n ${deployment_environment_openldap_viyaadminspassword}\n"


# ########################
# ##        WAIT       ###
# ########################
# while true;
# do
# kubectl get pods -o wide -n ${deployment_environment} | sed -n "1,56p"
# sleep 2
# kubectl get pods -o wide -n ${deployment_environment} | sed -n '57,$p'
# sleep 5
# for i in sas-consul-server-0 sas-rabbitmq-server-0 sas-cachelocator-0 sas-cacheserver-0 sas-cas-server-default-controller;  do 
# echo "POD: $i"
# kubectl describe pods $i | tail -n5
# done
# sleep 10
# echo ""
# done