#!/usr/bin/env bash
# You may overwrite the 7 defaults, but provide all of them: 
# ./deploy_rh_sso.sh namespace1 keycloak3 realm2 ..  
# Else just run with defaults # ./deploy_rh_sso.sh 

echo "Started running.."

NAMESPACE=${1:-idpdemo}
KEYCLOAK=${2:-keycloak}
REALMNAME=${3:-realm}
REALMCLIENT=${4:-client}
CLIENTSECRET=${5:-\"$(openssl rand -base64 14)\"}
OCPUSERNAME=${6:-testuser1}
OCPUSERPASSWORD=${7:-\"$(openssl rand -base64 14)\"}

OCPOATHURL=\"$(oc cluster-info | grep -o 'https://[^ ]*' | awk '{print $1}' | sed 's|api|oauth-openshift.apps|; s|:6443|/*|')\"
CLUSTEREXTERNALID=$(oc get clusterversion -o jsonpath='{.items[].spec.clusterID}{"\n"}')
CLUSTERID=$(rosa describe cluster -c "$CLUSTEREXTERNALID" | grep -m1 ID | awk '{print $2}')
CLUSTERNAME=$(rosa describe cluster -c $CLUSTERID | grep Name -m1 | awk '{print$2}')


# Login as  cluster admin before you execute.
echo "Confirm current oc user is a cluster admin."
if [[ "$(oc whoami)" != "$(oc describe groups.user.openshift.io cluster-admins | grep '^Users:' | awk '{print $2}')" ]]; then
echo "Please login to OCP as an admin user and try again."
exit 0
fi


#Bring yamls with curl
echo "Getting needed yamls"
curl --remote-name-all k4L  https://raw.githubusercontent.com/tshefi/deploy_rhsso/main/{CreateKeycloakPod.yaml,CreateNamespace_InstallRHSSO.yaml,CreateRealm_RealmClient_RealmUser.yaml}

#Populate variables
echo "Substituting paramaters on yaml files.."
sed -i "s|NAMESPACE|$NAMESPACE|g;       \
        s|KEYCLOAK|$KEYCLOAK|g;         \
        s|REALMNAME|$REALMNAME|g;       \
        s|REALMCLIENT|$REALMCLIENT|g;   \
        s|CLIENTSECRET|$CLIENTSECRET|g; \
        s|OCPOATHURL|$OCPOATHURL|g;     \
        s|OCPUSERNAME|$OCPUSERNAME|g;   \
        s|OCPUSERPASSWORD|$OCPUSERPASSWORD|g; \
        s/\x1B\[[0-9;]*[JKmsu]//g  " *.yaml

echo "Running first yaml."
oc apply -f  CreateNamespace_InstallRHSSO.yaml -n $NAMESPACE

echo "waiting for operator deployment to complete, ~1m."
sleep 15
oc wait --for=condition=Available deployment/rhsso-operator -n $NAMESPACE --timeout=300s
echo "RH sso operator is now ready, creating keycloak pod."
oc apply -f CreateKeycloakPod.yaml -n $NAMESPACE

echo "Waiting for keycloak-0 pod ready state, ~1m."
sleep 65
oc wait --for=condition=Ready=true pod/keycloak-0 -n $NAMESPACE --timeout=180s
echo "Creating realm, realm client and realm user."
oc apply -f CreateRealm_RealmClient_RealmUser.yaml -n $NAMESPACE


#Output TF stuff
echo "The OCP username is:"$OCPUSERNAME
echo "Userpassword is:"$OCPUSERPASSWORD
echo "To delete project $NAMESPACE delete these manually: user,client,realm, else project will remain forever in terminating state, bug??.\n"

echo "Just add your token on terraform.tfvars"
echo "token = \"add yours here..\"" | tee terraform.tfvars
echo url = $(rosa whoami | grep API | awk '{print $3}') | tee -a terraform.tfvars
echo cluster_id = $CLUSTERID | tee -a terraform.tfvars
echo openid_client_id = $REALMCLIENT | tee -a terraform.tfvars
echo openid_client_secret = $CLIENTSECRET | tee -a terraform.tfvars
echo "openid_issuer = \"https://$(oc get route keycloak --template='{{ .spec.host }}' -n "$NAMESPACE")/auth/realms/$REALMNAME\"" | tee -a terraform.tfvars
echo openid_claims = "{
       email             = ["email"]
       name              = ["name"]
       preferredUsername = ["preferred_username"]
     }" | tee -a terraform.tfvars
echo openid_ca = \"$(oc get secret $CLUSTERNAME-primary-cert-bundle-secret -n openshift-ingress -ojsonpath='{.data.tls\.crt}' | base64 --decode | awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}')\" | tee -a terraform.tfvars
