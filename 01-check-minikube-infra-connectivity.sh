#!/usr/bin/env bash

. common.sh

my-kubectl_pod_running() {
    local context=$1
    podstatus=$(kubectl --context=$context get pod my-kubectl -o jsonpath='{.status.phase}')
    if [[ "${podstatus}" == "Running" ]]
    then
        echo "0"
        return
    fi
    echo "1"
}

kubectl config view --flatten > kubeconfig
([ $? -eq 0 ] && log::info "generated kubeconfig") || log::error "Could not generate kubeconfig"


log::info "kubeconfig -> $(pwd)/kubeconfig"


for CLUSTERNAME in "${clusters[@]}"; do
 #   kubectl --context=${CLUSTERNAME} create -f my-kubectl.yaml;
    cat <<'EOF' | kubectl --context=${CLUSTERNAME} create -f -
apiVersion: v1
kind: Pod
metadata:
  name: my-kubectl
  namespace: default
spec:
  containers:
  - name: my-kubectl
    image: busybox
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
EOF
    wait_until "pod_in_namespace_for_context_is_running my-kubectl default ${CLUSTERNAME}" 10 45
done




for CLUSTERNAME in "${clusters[@]}"
do
    kubectl --context ${CLUSTERNAME} cp kubeconfig my-kubectl:kubeconfig;
    ([ $? -eq 0 ] && log::info "kubeconfig copied into my-kubectl in  ${CLUSTERNAME}") || ( log::error "Couldn't copy kubeconfig in  ${CLUSTERNAME}" && exit -1; )
    kubectl --context ${CLUSTERNAME} cp $(readlink -e $(which kubectl)) my-kubectl:kubectl;
     ([ $? -eq 0 ] && log::info "kubectl copied to my-kubectl in  ${CLUSTERNAME} ") || ( log::error "Couldn't copy kubectl in ${CLUSTERNAME}" && exit -1; )
done

for((i=0;i<${#clusters[@]};i++))
do for((j=0;j<${#clusters[@]};j++))
   do  [ "${clusters[$i]}" != "${clusters[$j]}" ] && kubectl --context=${clusters[$i]} exec -it my-kubectl -- /kubectl --kubeconfig=/kubeconfig --context=${clusters[$j]} cluster-info
   done
done

for((i=0;i<${#clusters[@]};i++))
do
    kubectl  --context=${clusters[$i]} delete pod my-kubectl --wait=false;
done
