
To avoid messing ~/.kube/config

```shell
$ export KUBECONFIG=$(mktemp -t argoFM.XXXXXXXX.kubeconfig)
```

To create 3 minikube clusters: `mgmt`, `cluster1` and `cluster2`.

```shell
$ ./00-boostrap-minikube-infra.sh
```

The script configure `minikube` networks to see each others.

This is optional but in case cluster pods cannot see each other you may want to chec connectivity.
```shell
$ ./01-check-minikube-infra-connectivity.sh
```

To run the the demo.

```shell
$ ./demo.sh
```


To cleanup all the `minikube`s

```shell
$ ./9-cleanup-minikube-infra.sh
```
