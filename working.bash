# Generate the TF plan corresponding to the AKS cluster with multiple node pools
cd /deployment_resources/aks/viya4-iac-azure
terraform plan -input=false \
    -var-file=./$deployment_name.tfvars \
    -out ./$deployment_name-aks.plan
	
#    <<<< YOU ARE HERE

cd /deployment_resources/aks/viya4-iac-azure
TFPLAN=$deployment_name-aks.plan
#terraform show ${TFPLAN}
##################################################
##### Deploy the AKS cluster with the TF plan ####
##################################################
time terraform apply "./${TFPLAN}" 2>&1 \
| tee -a /deployment_resources/aks/viya4-iac-azure/$(date +%Y%m%dT%H%M%S)_terraform-apply.log
##################################################


##################### DESTROY ####################
# Generate the TF plan corresponding to the AKS cluster with multiple node pools
cd /deployment_resources/aks/viya4-iac-azure
terraform plan -destroy -input=false -var-file=./$deployment_name.tfvars -out ./$deployment_name-aks-destroy.plan

time terraform apply ./$deployment_name-aks-destroy.plan 2>&1 \
| tee -a /deployment_resources/aks/viya4-iac-azure/$(date +%Y%m%dT%H%M%S)_terraform-destroy.log







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



### !!! YOU HAVE A mirorrmgr session running !!!###

screen -r -S mirrormgr






kubectl -n proving1 get po | grep "0/" | awk '{ print $1 }' | xargs -I % kubectl delete pod % -n proving1



while true;
do
kubectl get pods -o wide -n proving1 | sed -n "1,56p"
sleep 2
kubectl get pods -o wide -n proving1 | sed -n '57,$p'
sleep 5
for i in sas-feature-flags-fbbd8f648-gpbh9;  do 
echo "POD: $i"
kubectl describe pods $i | tail -n5
done
sleep 10
echo ""
done

https://sandpit1.oz.sas.com