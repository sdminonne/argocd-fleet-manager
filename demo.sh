#!/usr/bin/env bash

. demo-magic.sh

. common.sh

command -v clusteradm >/dev/null 2>&1 || { log::error >&2 "can't find clusteradm.  Aborting."; exit 1; }
#check pre-requisities: TODO check version
command -v argocd >/dev/null 2>&1 || { log::error >&2 "can't find argocd. Aborting."; exit 1; }

HUBIP=$(minikube -p ${HUB} ip)
HUBURL=https://${HUBIP}:8443

#commaseparatedmanagedcluster=""
#delim=""

clear

#################
# Install ArgoCD
#################
log::info "Install ArgoCD"
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) create namespace argocd"
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply -n argocd -f manifests/argocd/"
wait_until "all_pods_in_namespace_for_context_are_running argocd $(get_client_context_from_cluster_name ${MGMT})" 5 60
kubectl config use-context  $(get_client_context_from_cluster_name ${MGMT})
kubectl config set-context --current --namespace=argocd
argocd cluster list

########################
# Add clusters to argo
#######################
for mc in "${managedclusters[@]}"; do
    pe "argocd cluster add ${mc} -y"
done

argocd cluster list

exit

log::info "Let's look at what it installed on ${managedclusters}"

pe "kubectl --context ${managedclusters} get sa  argocd-manager -n kube-system -o yaml"

pe "kubectl --context ${managedclusters} get clusterrolebinding argocd-manager-role-binding -o yaml"

pe "kubectl --context ${managedclusters} get clusterrole argocd-manager-role"

#kubectl get secret cluster-192.168.50.40-2497131181 -o jsonpath='{.data.config}'  | base64 -d | jq -r > $(mktemp -t ${managedclusters}.XXXX.auth)
#kubectl get secret cluster-192.168.50.40-2497131181 -o jsonpath='{.data.config}'  | base64 -d | jq -r > $(mktemp -t ${managedclusters}.XXXX.auth)

exit
