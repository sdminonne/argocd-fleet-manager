#!/usr/bin/env bash

. demo-magic.sh

. common.sh


command -v kubectl >/dev/null 2>&1 || { log::error >&2 "can't find kubectl.  Aborting."; exit 1; }

#check pre-requisities: TODO check version
command -v argocd >/dev/null 2>&1 || { log::error >&2 "can't find argocd. Aborting."; exit 1; }


command -v helm >/dev/null 2>&1 || { log::error >&2 "can't find helm. Aborting."; exit 1; }


command -v curl >/dev/null 2>&1 || { log::error >&2 "can't find curl. Aborting."; exit 1; }

MGMTIP=$(minikube -p "${MGMT}" ip)
MGMTURL=https://${MGMTIP}:8443

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

pe "argocd cluster list"

########################
# Add clusters to argo
#######################
for mc in "${managedclusters[@]}"; do
    pe "kubectl --context $(get_client_context_from_cluster_name ${mc}) config view --minify --flatten > ${mc}.kubeconfig"
    pe "argocd cluster add ${mc} --kubeconfig= ${mc}.kubeconfig -y"
done

pe "argocd cluster list"



#####################################
# Creates ingress-nginx on clusters
####################################
#cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply -n argocd -f -
#apiVersion: argoproj.io/v1alpha1
#kind: ApplicationSet
#metadata:
#  name: ingress-nginx
#spec:
#  generators:
#  - list:
#      elements:
#      - cluster: ${managedclusters[0]}
#        url: https://$(minikube -p ${managedclusters[0]} ip):8443
#      - cluster: ${managedclusters[1]}
#        url: https://$(minikube -p ${managedclusters[1]} ip):8443
#  template:
#    metadata:
#      name: '{{cluster}}-nginx-ingress'
#    spec:
#      project: default
#      syncPolicy:
#        automated:
#          prune: true
#          selfHeal: true
#        syncOptions:
#          - CreateNamespace=true
#      source:
#        chart: nginx-ingress
#        repoURL: https://helm.nginx.com/stable
#        targetRevision: 0.17.1
#        helm:
#          releaseName: nginx-stable
#      destination:
#        server: '{{url}}'
#        namespace: ingress-nginx
#  syncPolicy:
#    preserveResourcesOnDeletion: true
#EOF



#######################
# Deploy cert-manager
#######################

cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply  -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
spec:
  destination:
    namespace: cert-manager
    server: https://kubernetes.default.svc
  project: default
  source:
    chart: cert-manager
    helm:
      parameters:
        - name: installCRDs
          value: "true"
    repoURL: https://charts.jetstack.io
    targetRevision: v1.11.0
  syncPolicy:
    automated: {}
    syncOptions:
      - CreateNamespace=true
EOF


wait_until "crd_defined_for_context certificates.cert-manager.io $(get_client_context_from_cluster_name ${MGMT})" 10 120
wait_until "crd_defined_for_context issuers.cert-manager.io $(get_client_context_from_cluster_name ${MGMT})" 10 120
wait_until "all_pods_in_namespace_for_context_are_running cert-manager  $(get_client_context_from_cluster_name ${MGMT})" 10 120


##################################
# Deploy self-signed  cert issuer
##################################
cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply  -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: cert-manager
spec:
  selfSigned: {}
EOF

#################
# generate certs
#################
for mc in "${managedclusters[@]}"; do
    cat <<EOF | kubectl --context $(get_client_context_from_cluster_name ${MGMT}) apply  -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${mc}-cert
  namespace: cert-manager
spec:
  secretName: ${mc}-tls
  secretTemplate:
    annotations:
      cluster-url: $(minikube -p ${mc} ip)
    labels:
      cluster: ${mc}
  duration: 24h
  renewBefore: 12h
  secretTemplate:
    labels:
      cluster: ${mc}
  commonName: ${mc}
  subject:
    organizations:
      - argocd-fleet-manager
    organizationalUnits:
      - argo
  privateKey:
    algorithm: ECDSA
    size: 256
  ipAddresses:
    - $(minikube -p ${mc} ip)
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer
    group: cert-manager.io
EOF
done

#TODO wait_until "certificates.cert-manager.io in namespace for context READY"
#TODO wait_until "certificates.cert-manager.io in namespace for context READY"


################################
# Install gitea on mgmt cluter
################################
#from https://gitea.com/gitea/helm-chart/src/branch/main/values.yaml
#username: gitea_admin
#password: r8sA8CPHD9!bt6d
#email: "gitea@local.domain"

GITEAUSERNAME='gitea_admin'
GITEAPASSWORD='r8sA8CPHD9!bt6d'

log::info "Creating a GIT repository on ${MGMT} cluster using helm charts for GITEA -> https://gitea.io/en-us"
pe "helm --kube-context $(get_client_context_from_cluster_name ${MGMT}) install gitea gitea-charts/gitea  --namespace default --create-namespace --set service.http.type=LoadBalancer"

# TODO for ariplane mode retrieve image gitea/gitea:1.19.1
wait_until "pod_in_namespace_for_context_is_running gitea-0 default $(get_client_context_from_cluster_name ${MGMT})" 10 120

#TODO for "airplane mode" retrieve image  docker.io/bitnami/memcached:1.6.19-debian-11-r3
wait_until "deployment_in_namespace_for_context_up_and_running gitea-memcached default $(get_client_context_from_cluster_name ${MGMT})" 10 120

#TODO for airplane mode retrieve image docker.io/bitnami/postgresql:15.2.0-debian-11-r14
wait_until "pod_in_namespace_for_context_is_running gitea-postgresql-0 default $(get_client_context_from_cluster_name ${MGMT})" 10 120


#patch the gitea svc on ${MGMT} cluster with the minikube IP address
kubectl --context $(get_client_context_from_cluster_name ${MGMT}) -n default patch svc gitea-http -p "{\"spec\":{\"externalIPs\":[\"${MGMTIP}\"]}}"

#gets the GITEA port to check when/if svc is available
GITEAPORT=$(kubectl --context $(get_client_context_from_cluster_name ${MGMT}) -n default get svc gitea-http -o jsonpath='{.spec.ports[0].nodePort}')

#check when/if svc is available
wait_until "http_endpoint_is_up http://${MGMTIP}:${GITEAPORT}" 10 120



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
    - http:
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
      - $(minikube -p cluster1 ip)
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
#TODO: adds the certificates
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
      - cluster: ${managedclusters[1]}
        url: https://$(minikube -p ${managedclusters[1]} ip):8443
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
