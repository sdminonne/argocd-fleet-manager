This sets of script generate a mini CA through openssl.

```shell
$ ./check-or-generate-root.sh
...
```

```shell
$ ./check-or-generate-intermediate.sh
```

At the end of the run of these two scripts you hould have these files:

```shell
.../mini-ca/root/argo_root_cert.pem
.../mini-ca/intermediate/private/argo_intermediate_private_key.pem"
.../mini-ca/intermediate/argo_intermediate_cert.pem
```

The first one `.../mini-ca/root/argo_root_cert.pem` is the Root CA that you've to add and trust to your local machine; instead `.../mini-ca/intermediate/argo_intermediate_cert.pem` and `.../mini-ca/intermediate/private/argo_intermediate_private_key.pem` are the intermediate CA to create the CA-issuer for cert-manager.


Now let's add the root CA as a trusted certificate authority.

``` shell
$ sudo cp ./mini-ca/root/argo_root_cert.pem /etc/pki/ca-trust/source/anchors/argo_root_cert.pem
```

```shell
$ sudo update-ca-trust
```



To remove the root CA

`` shell
$ sudo rm /etc/pki/ca-trust/source/anchors/argo_root_cert.pem
```

```shell
$ sudo update-ca-trust
```
02
Thanks to https://github.com/PacktPublishing/Demystifying-Cryptography-with-OpenSSL-3/tree/main/Chapter12/mini-ca
and https://www.devdungeon.com/content/how-add-trusted-ca-certificate-centosfedora
