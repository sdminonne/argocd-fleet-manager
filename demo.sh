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

#################
# Install ArgoCD
#################
log::info "Install ArgoCD"
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) create namespace argocd"
pe "kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply -n argocd -f manifests/argocd/" # we install only Argo Core
wait_until "all_pods_in_namespace_for_context_are_running argocd $(get_client_context_from_cluster_name ${MGMT})" 10 120

pe "kubectl config use-context  $(get_client_context_from_cluster_name ${MGMT})"
pe "kubectl config set-context --current --namespace=argocd"


################################
# Creating Argo default project
################################
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

################################
# Install gitea on mgmt cluter
################################
#from https://gitea.com/gitea/helm-chart/src/branch/main/values.yaml
#username: gitea_admin
#password: r8sA8CPHD9!bt6d
#email: "gitea@local.domain"

GITEAUSERNAME='gitea_admin'
GITEAPASSWORD='r8sA8CPHD9!bt6d'

log::info "Creating a GIT repository on ${MGMT} cluster using helm charts for GITEA see https://gitea.io/en-us"
pe "helm --kube-context $(get_client_context_from_cluster_name ${MGMT}) install gitea gitea-charts/gitea  --namespace default --create-namespace --set service.http.type=LoadBalancer"

# TODO for ariplane mode retrieve image gitea/gitea:1.19.1
wait_until "pod_in_namespace_for_context_is_running gitea-0 default $(get_client_context_from_cluster_name ${MGMT})" 10 120

#TODO for "airplane mode" retrieve image  docker.io/bitnami/memcached:1.6.19-debian-11-r3
wait_until "deployment_in_namespace_for_context_up_and_running gitea-memcached default $(get_client_context_from_cluster_name ${MGMT})" 10 120

#TODO for airplane mode retrieve image docker.io/bitnami/postgresql:15.2.0-debian-11-r14
wait_until "pod_in_namespace_for_context_is_running gitea-postgresql-0 default $(get_client_context_from_cluster_name ${MGMT})" 10 120

#gets the gitea ip addres. The ${MGMT} cluster at the moment
MGMTIP=$(minikube -p "${MGMT}" ip)

#patch the gitea svc on ${MGMT} cluster with the minikube IP address
kubectl --context $(get_client_context_from_cluster_name ${MGMT}) -n default patch svc gitea-http -p "{\"spec\":{\"externalIPs\":[\"${MGMTIP}\"]}}"

#gets the GITEA port to check when/if svc is available
GITEAPORT=$(kubectl --context $(get_client_context_from_cluster_name ${MGMT}) -n default get svc gitea-http -o jsonpath='{.spec.ports[0].nodePort}')

#check when/if svc is available
wait_until "http_endpoint_is_up http://${MGMTIP}:${GITEAPORT}" 10 120

log::info "OK you can find git repository at http://${MGMTIP}:${GITEAPORT}"
log::info "Gitea user: ${GITEAUSERNAME}"
log::info "Gitea password: ${GITEAPASSWORD}"

########################
# Add clusters to argo
#######################
pe "argocd --core=true cluster list"

for mc in "${managedclusters[@]}"; do
    pe "kubectl --context $(get_client_context_from_cluster_name ${mc}) config view --minify --flatten > ${mc}.kubeconfig"
    pe "argocd --core=true cluster add ${mc} --kubeconfig= ${mc}.kubeconfig -y"
done

pe "argocd --core=true cluster list"

#########################################
# Create secret to deploy apps and appset
#########################################
cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply  -f -
apiVersion: argoproj.io/v1alpha1
apiVersion: v1
kind: Secret
metadata:
  name: in-cluster
  labels:
    app.kubernetes.io/part-of: argocd
    argocd.argoproj.io/secret-type: cluster
    cluster-type: management
type: Opaque
stringData:
  server: https://kubernetes.default.svc
EOF


log::info "Creating cert-manager in clusteraddons"

log::info "creating clusteraddons GIT repo in http://${MGMTIP}:${GITEAPORT}"
curl -u 'gitea_admin:r8sA8CPHD9!bt6d' \
    -X POST  "http://${MGMTIP}:${GITEAPORT}/api/v1/user/repos" \
    -H "Content-Type: application/json" \
    -H "accept: application/json" \
    -d "{\"name\": \"clusteraddons\", \"private\": false}" \
    -i

CLUSTERADDONSTMP=$(mktemp -d)/clusteraddons
mkdir -p ${CLUSTERADDONSTMP}/cert-manager/
git init ${CLUSTERADDONSTMP}
cp  ${ROOTDIR}/manifests/cert-manager/cert-manager.yaml ${CLUSTERADDONSTMP}/cert-manager/cert-manager.yaml 
cd ${CLUSTERADDONSTMP}
git add ${CLUSTERADDONSTMP}/cert-manager
git remote add origin http://${MGMTIP}:${GITEAPORT}/gitea_admin/clusteraddons
git commit -s -a -m 'Ἐν ἀρχῇ ἦν ὁ λόγος'
git push 'http://gitea_admin:r8sA8CPHD9!bt6d'@${MGMTIP}:${GITEAPORT}/gitea_admin/clusteraddons.git HEAD


cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply  -f -
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cert-manager
spec:
  generators:
  - matrix:
      generators:
        - git:
            repoURL: http://${MGMTIP}:${GITEAPORT}/gitea_admin/clusteraddons.git
            revision: HEAD
            directories:
            - path: cert-manager
        - clusters:
            selector:
              matchLabels:
                argocd.argoproj.io/secret-type: cluster
                cluster-type: management
  template:
    metadata:
      name: 'cert-manager'
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: http://${MGMTIP}:${GITEAPORT}/gitea_admin/clusteraddons.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: '{{server}}'
        namespace: '{{path}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
  syncPolicy:
    preserveResourcesOnDeletion: true
EOF



log::info "waiting for cert-manager to bootstrap"
sleep 10
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





#####################################################################
# and now through GitOps the CA-issuer and the certificate requests
#####################################################################
log::info "Creating cert-manager Issuer"
cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply  -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: ca-issuer
  namespace: cert-manager
spec:
  ca:
    secretName: ca-key-pair
EOF

#TODO add check issuer ready


for mc in "${managedclusters[@]}"; do
cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply  -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${mc}-cert
  namespace: cert-manager
spec:
  secretName: ${mc}-tls
  duration: 24h
  renewBefore: 12h
  secretTemplate:
    annotations:
      syncrets-namespace: guestbook
    labels:
      cluster: ${mc}
  commonName: ${mc}
  subject:
    organizations:
      - argocd-fleet-manager
    organizationalUnits:
      - argo
  privateKey:
    algorithm: RSA
    size: 2048
  usages:
    - server auth
  dnsNames:
    - ${mc}
  issuerRef:
    name: ca-issuer
    kind: Issuer
    group: cert-manager.io
EOF
done


#TODO check certs ready
#TODO check if secret is found in cert-manager


#To test whter {{cluster}} is propagated to Certificate...

exit

#Create syncrets in gitea

#Create certs


1) Deploy cert-manager
2) Create CA-Issuer
3) Deploy syncrets
4) Create certs
5) Deploy Guestbook

#1---4
#Bisogna creare
#http://${MGMTIP}:${GITEAPORT}/gitea_admin/cluster-addons/management/cert-manager
#http://${MGMTIP}:${GITEAPORT}/gitea_admin/cluster-addons/management/syncrets




#TODO wait_until "certificates.cert-manager.io in namespace for context READY"
#TODO wait_until "certificates.cert-manager.io in namespace for context READY"

###########################
# creating guestbook on git
###########################
log::info "creating guestbook GIT repo in http://${MGMTIP}:${GITEAPORT}"
curl -u 'gitea_admin:r8sA8CPHD9!bt6d' \
    -X POST  "http://${MGMTIP}:${GITEAPORT}/api/v1/user/repos" \
    -H "Content-Type: application/json" \
    -H "accept: application/json" \
    -d "{\"name\": \"guestbook\", \"private\": false}" \
    -i
#TODO check $?

GUESTBOOKTMP=$(mktemp -d)/guestbook
git init ${GUESTBOOKTMP}
cd ${GUESTBOOKTMP}

for mc in "${managedclusters[@]}"; do
    mkdir -p  ${GUESTBOOKTMP}/${mc}
    cat << 'EOF' >  ${GUESTBOOKTMP}/${mc}/guestbook-ui-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: guestbook-ui
spec:
  replicas: 1
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app: guestbook-ui
  template:
    metadata:
      labels:
        app: guestbook-ui
    spec:
      containers:
      - image: gcr.io/heptio-images/ks-guestbook-demo:0.1
        name: guestbook-ui
        ports:
        - containerPort: 80
EOF
    git add ${GUESTBOOKTMP}/${mc}/guestbook-ui-deployment.yaml
    cat << EOF >  ${GUESTBOOKTMP}/${mc}/guestbook-ui-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: guestbook-ui
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: guestbook-ui
EOF
    git add ${GUESTBOOKTMP}/${mc}/guestbook-ui-svc.yaml
    cat << EOF >  ${GUESTBOOKTMP}/${mc}/guestbook-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
    name: guestbookl-ingress
spec:
    rules:
    - host: ${mc}
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: guestbook-ui
              port:
                number: 80
    tls:
    - hosts:
      - ${mc}
      secretName: ${mc}-tls
EOF
    git add ${GUESTBOOKTMP}/${mc}/guestbook-ingress.yaml
done

git remote add origin http://${MGMTIP}:${GITEAPORT}/gitea_admin/guestbook.git
git commit -s -a -m 'Ἐν ἀρχῇ ἦν ὁ λόγος'
git push 'http://gitea_admin:r8sA8CPHD9!bt6d'@${MGMTIP}:${GITEAPORT}/gitea_admin/guestbook.git HEAD
cd -

log::info "GIT repo http://${MGMTIP}:${GITEAPORT}/gitea_admin/guestbook.git created"

#####################################
# Now load the applications
#####################################
cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply -f -
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  generators:
  - list:
      elements:
      - cluster: ${managedclusters[0]}
        url: https://$(minikube -p ${managedclusters[0]} ip):8443
  template:
    metadata:
      name: '{{cluster}}-guestbook'
    spec:
      project: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
      source:
        repoURL: http://${MGMTIP}:${GITEAPORT}/gitea_admin/guestbook.git
        targetRevision: HEAD
        path: '{{cluster}}'
      destination:
        server: '{{url}}'
        namespace: guestbook
  syncPolicy:
    preserveResourcesOnDeletion: true
EOF




#####################################
# Now sync the applications
#####################################
for mc in "${managedclusters[@]}"; do
    pe "argocd app sync ${mc}-guestbook"
done


pe "kubectl get apps"

exit
