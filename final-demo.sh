#!/usr/bin/env bash

ROOTDIR=$(git rev-parse --show-toplevel)

. ${ROOTDIR}/demo-magic.sh

. ${ROOTDIR}/common.sh


command -v kubectl >/dev/null 2>&1 || { log::error >&2 "can't find kubectl.  Aborting."; exit 1; }

#check pre-requisities: TODO check version
command -v argocd >/dev/null 2>&1 || { log::error >&2 "can't find argocd. Aborting."; exit 1; }

command -v helm >/dev/null 2>&1 || { log::error >&2 "can't find helm. Aborting."; exit 1; }

command -v curl >/dev/null 2>&1 || { log::error >&2 "can't find curl. Aborting."; exit 1; }

clear


#########################
# Installing cert-manager
#########################
log::info "Intalling cert-manager"
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply -f ${ROOTDIR}/manifests/cert-manager/cert-manager.yaml"


log::info "waiting for cert-manager to bootstrap"
sleep 10 # TODO add a wait_until based on deployment creation (unsure whether can avoid the sleep)
wait_until "crd_defined_for_context certificates.cert-manager.io $(get_client_context_from_cluster_name ${MGMT})" 10 120
wait_until "crd_defined_for_context issuers.cert-manager.io $(get_client_context_from_cluster_name ${MGMT})" 10 120
wait_until "all_pods_in_namespace_for_context_are_running cert-manager  $(get_client_context_from_cluster_name ${MGMT})" 10 120

##########################################
# Deploy cert-manager ca-issuer and certs
##########################################
log::info "Let's create the secret needed for the CA-issuer"
kubectl --context $(get_client_context_from_cluster_name ${MGMT}) -n cert-manager create secret tls ca-key-pair \
  --key="${ROOTDIR}/mini-ca/intermediate/private/argo_intermediate_private_key.pem" \
  --cert="${ROOTDIR}/mini-ca/intermediate/argo_intermediate_cert.pem"
#TODO find a way to deploy this in a more gitops way (external-secret or sealed-secret)

################################################
# Installing the issuer
################################################
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply -f ${ROOTDIR}/manifests/cert-manager/ca-issuer.yaml"
# TODO adds ca-isuer ready
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) get clusterissuers -n cert-manager"

################################
# Install gitea on mgmt cluter aka my-git.io
################################
#from https://gitea.com/gitea/helm-chart/src/branch/main/values.yaml
#username: gitea_admin
#password: r8sA8CPHD9!bt6d
#email: "gitea@local.domain"

GITEAUSERNAME='gitea_admin'
GITEAPASSWORD='r8sA8CPHD9!bt6d'
GITEANS=gitea

log::info "Creating a GIT server on ${MGMT} cluster using helm charts for GITEA see https://gitea.io/en-us"
pe "helm --kube-context $(get_client_context_from_cluster_name ${MGMT}) install gitea gitea-charts/gitea  --namespace ${GITEANS} --create-namespace"
log::info "Adding ingress to gitea (cert-manager generates the certificate)"
cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) -n ${GITEANS} apply  -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitea-ingress
  labels:
    app: gitea-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: ca-issuer
spec:
  rules:
  - host: my-git.io
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: gitea-http
              port:
                number: 3000
  tls:
  - hosts:
    - my-git.io
    secretName: my-git-cert
EOF

# TODO for ariplane mode retrieve image gitea/gitea:1.19.1
wait_until "pod_in_namespace_for_context_is_running gitea-0 ${GITEANS} $(get_client_context_from_cluster_name ${MGMT})" 10 120

#TODO for "airplane mode" retrieve image  docker.io/bitnami/memcached:1.6.19-debian-11-r3
wait_until "deployment_in_namespace_for_context_up_and_running gitea-memcached ${GITEANS} $(get_client_context_from_cluster_name ${MGMT})" 10 120

#TODO for airplane mode retrieve image docker.io/bitnami/postgresql:15.2.0-debian-11-r14
wait_until "pod_in_namespace_for_context_is_running gitea-postgresql-0 ${GITEANS} $(get_client_context_from_cluster_name ${MGMT})" 10 120

#check when/if svc is available
wait_until "https_endpoint_is_up https://my-git.io" 10 120

log::info "OK you can find git server at https://my-git.io"
log::info "Gitea user: ${GITEAUSERNAME}"
log::info "Gitea password: ${GITEAPASSWORD}"

# Gitea now should be up and running

#################
# Install ArgoCD
#################
# 1. Installing the core
log::info "Installing ArgoCD"
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) create namespace argocd"
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply -n argocd -f manifests/argocd/" # we install only Argo Core
wait_until "all_pods_in_namespace_for_context_are_running argocd $(get_client_context_from_cluster_name ${MGMT})" 10 120

pe "kubectl config use-context  $(get_client_context_from_cluster_name ${MGMT})"
pe "kubectl config set-context --current --namespace=argocd"

# 2. Creating Argo default project
log::info "Creating Argo default project"
cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply  -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
spec:
  sourceRepos:
    - '*'
  destinations:
    - namespace: '*'
      server: '*'
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
EOF


#################
# Deploy syncrets
#################
log::info "Deploying syncrets"
#SYNCRETSDIR=$(mktemp -d /tmp/syncrets.XXXX)
#git clone https://github.com/sdminonne/syncrets.git ${SYNCRETSDIR}
SYNCRETSDIR=~/dev/sdminonne/syncrets/src/github.com/sdminonne/syncrets/
pushd ${SYNCRETSDIR}
make build
make image
make CLUSTER=${MGMT} push-image
kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply  -f ${SYNCRETSDIR}/deployment/syncrets.yaml
popd
wait_until "all_pods_in_namespace_for_context_are_running cert-manager  $(get_client_context_from_cluster_name ${MGMT})" 10 120


log::info "creating clusteraddons GIT repo in https://my-git.io"
curl  -u 'gitea_admin:r8sA8CPHD9!bt6d' \
    -X POST  "https://my-git.io/api/v1/user/repos" \
    -H "Content-Type: application/json" \
    -H "accept: application/json" \
    -d "{\"name\": \"clusteraddons\", \"private\": false}" \
    -i

CLUSTERADDONSTMP=$(mktemp -d)/clusteraddons
mkdir -p ${CLUSTERADDONSTMP}
git init ${CLUSTERADDONSTMP}
pe "cp  -r ${ROOTDIR}/manifests/guestbook ${CLUSTERADDONSTMP}"
pushd ${CLUSTERADDONSTMP}
git remote add origin 'https://gitea_admin:r8sA8CPHD9!bt6d'@my-git.io/gitea_admin/clusteraddons.git
pe "git add ${CLUSTERADDONSTMP}/guestbook"
pe "git commit -s -a -m 'To add guestbook'"
pe "git push origin HEAD"
popd

###########################################################################
# Adds repo to argocd to trust  https://my-git.io/gitea_admin/clusteraddons
###########################################################################
pe "argocd repo add  --insecure-skip-server-verification https://my-git.io/gitea_admin/clusteraddons.git"
