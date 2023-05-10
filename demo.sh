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


################################
# Install gitea on mgmt cluter
################################
pe "helm install gitea gitea-charts/gitea"
pe "helm --kube-context --context $(get_client_context_from_cluster_name ${MGMT}) install gitea gitea-charts/gitea  --set service.http.type=LoadBalancer"
#TODO wait until gitea is up and running

MGMTIP=$(minikube -p mgmt ip)
GITEAPORT=$(kubectl --context $(get_client_context_from_cluster_name ${MGMT}) get svc gitea-http -o jsonpath='{.spec.ports[0].nodePort}')

#from https://gitea.com/gitea/helm-chart/src/branch/main/values.yaml
#username: gitea_admin
#password: r8sA8CPHD9!bt6d
#email: "gitea@local.domain"


# Create repo in gitea
curl -u 'gitea_admin:r8sA8CPHD9!bt6d' \
    -X POST  "http://${MGMTIP}:${GITEAPORT}/api/v1/user/repos" \
    -H "Content-Type: application/json" \
    -H "accept: application/json" \
    -d "{\"name\": \"my-repo\"}" \
    -i

cd /tmp
git init my-repo
cd /tmp/my-repo
echo "Hello git" > README.md
git add /tmp/my-repo/README.md
git remote add origin http://${MGMTIP}:${GITEAPORT}/gitea_admin/my-repo.git
git commit -s -a -m 'in the beginning'
git push origin HEAD



#################
# Install ArgoCD
#################
log::info "Install ArgoCD"
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) create namespace argocd"
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply -n argocd -f manifests/argocd/"
wait_until "all_pods_in_namespace_for_context_are_running argocd $(get_client_context_from_cluster_name ${MGMT})" 5 60

pe "kubectl config use-context  $(get_client_context_from_cluster_name ${MGMT})"
pe "kubectl config set-context --current --namespace=argocd"

pe "argocd cluster list"

########################
# Add clusters to argo
#######################
for mc in "${managedclusters[@]}"; do
    #kubectl --context $(get_client_context_from_cluster_name ${MGMT}) config view --minify --flatten > ${mc}.kubeconfig
    #pe "argocd cluster add ${mc} --kubeconfig= ${mc}.kubeconfig -y"
    pe "argocd cluster add ${mc} --kubeconfig= ${mc}.kubeconfig -y"
done

pe "argocd cluster list"

exit

log::info "Let's look at what it installed on ${managedclusters}"

pe "kubectl --context ${managedclusters} get sa  argocd-manager -n kube-system -o yaml"

pe "kubectl --context ${managedclusters} get clusterrolebinding argocd-manager-role-binding -o yaml"

pe "kubectl --context ${managedclusters} get clusterrole argocd-manager-role"

#kubectl get secret cluster-192.168.50.40-2497131181 -o jsonpath='{.data.config}'  | base64 -d | jq -r > $(mktemp -t ${managedclusters}.XXXX.auth)
#kubectl get secret cluster-192.168.50.40-2497131181 -o jsonpath='{.data.config}'  | base64 -d | jq -r > $(mktemp -t ${managedclusters}.XXXX.auth)

exit
