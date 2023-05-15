#!/usr/bin/env bash

. demo-magic.sh

. common.sh

kubectl config use-context  $(get_client_context_from_cluster_name ${MGMT})

command -v clusteradm >/dev/null 2>&1 || { log::error >&2 "can't find clusteradm.  Aborting."; exit 1; }
#check pre-requisities: TODO check version
command -v argocd >/dev/null 2>&1 || { log::error >&2 "can't find argocd. Aborting."; exit 1; }

MGMTIP=$(minikube -p ${MGMT} ip)
MGMTURL=https://${MGMTIP}:8443

clear


################################
# Install gitea on mgmt cluter
################################
pe "helm --kube-context $(get_client_context_from_cluster_name ${MGMT}) install gitea gitea-charts/gitea  --set service.http.type=LoadBalancer"

# TODO for ariplane mode retrieve image gitea/gitea:1.19.1
wait_until "pod_in_namespace_for_context_is_running gitea-0 default $(get_client_context_from_cluster_name ${MGMT})" 5 60

#TODO for "airplane mode" retrieve image  docker.io/bitnami/memcached:1.6.19-debian-11-r3
wait_until "deployment_in_namespace_for_context_up_and_running gitea-memcached default $(get_client_context_from_cluster_name ${MGMT})" 5 60

#TODO for airplane mode retrieve image docker.io/bitnami/postgresql:15.2.0-debian-11-r14
wait_until "pod_in_namespace_for_context_is_running gitea-postgresql-0 default $(get_client_context_from_cluster_name ${MGMT})" 5 60

GITEAPORT=$(kubectl --context $(get_client_context_from_cluster_name ${MGMT}) get svc gitea-http -o jsonpath='{.spec.ports[0].nodePort}')

kubectl --context $(get_client_context_from_cluster_name ${MGMT}) patch svc gitea-http -p "{\"spec\":{\"externalIPs\":[\"${MGMTIP}\"]}}"

#from https://gitea.com/gitea/helm-chart/src/branch/main/values.yaml
#username: gitea_admin
#password: r8sA8CPHD9!bt6d
#email: "gitea@local.domain"


# Create repo in gitea
curl -u 'gitea_admin:r8sA8CPHD9!bt6d' \
    -X POST  "http://${MGMTIP}:${GITEAPORT}/api/v1/user/repos" \
    -H "Content-Type: application/json" \
    -H "accept: application/json" \
    -d "{\"name\": \"guestbook\", \"private\": false}" \
    -i

cd /tmp
git init guestbook
cd /tmp/guestbook

for mc in "${managedclusters[@]}"; do
    mkdir -p  /tmp/guestbook/${mc}
    cat << 'EOF' >  /tmp/guestbook/${mc}/guestbook-ui-deployment.yaml
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
      - image: gcr.io/heptio-images/ks-guestbook-demo:0.2
        name: guestbook-ui
        ports:
        - containerPort: 80
EOF
    git add /tmp/guestbook/${mc}/guestbook-ui-deployment.yaml
    cat << EOF >  /tmp/guestbook/${mc}/guestbook-ui-svc.yaml
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
    git add /tmp/guestbook/${mc}/guestbook-ui-svc.yaml
done

git remote add origin http://${MGMTIP}:${GITEAPORT}/gitea_admin/guestbook.git
git commit -s -a -m 'Ἐν ἀρχῇ ἦν ὁ λόγος'
git push 'http://gitea_admin:r8sA8CPHD9!bt6d'@${MGMTIP}:${GITEAPORT}/gitea_admin/guestbook.git HEAD
cd -

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
    kubectl --context $(get_client_context_from_cluster_name ${mc}) config view --minify --flatten > ${mc}.kubeconfig
    #pe "argocd cluster add ${mc} --kubeconfig= ${mc}.kubeconfig -y"
    pe "argocd cluster add ${mc} --kubeconfig= ${mc}.kubeconfig -y"
done

pe "argocd cluster list"



cat <<EOF | kubectl create -f -
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  generators:
  - list:
      elements:
      - cluster: managedclusters[0]
        url: https://$(minikube -p ${managedclusters[0]} ip):8443
      - cluster: managedclusters[1]
        url: https://$(minikube -p ${managedclusters[1]} ip):8443
  template:
    metadata:
      name: '{{cluster}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: applicationset/examples/list-generator/guestbook/{{cluster}}
      destination:
        server: '{{url}}'
        namespace: guestbook

EOF


log::info "Let's look at what it installed on ${managedclusters}"

pe "kubectl --context ${managedclusters} get sa  argocd-manager -n kube-system -o yaml"

pe "kubectl --context ${managedclusters} get clusterrolebinding argocd-manager-role-binding -o yaml"

pe "kubectl --context ${managedclusters} get clusterrole argocd-manager-role"

#kubectl get secret cluster-192.168.50.40-2497131181 -o jsonpath='{.data.config}'  | base64 -d | jq -r > $(mktemp -t ${managedclusters}.XXXX.auth)
#kubectl get secret cluster-192.168.50.40-2497131181 -o jsonpath='{.data.config}'  | base64 -d | jq -r > $(mktemp -t ${managedclusters}.XXXX.auth)

exit
