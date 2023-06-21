This sets of script generate a mini CA through openssl.

```shell
$ ./check-or-generate-root.sh
...
```

```shell
$ ./check-or-generate-intermediate.sh
```


Now let's add the intermediate cert as a trusted certificate authority.

``` shell
$ sudo cp root/argo_root_cert.pem /etc/pki/ca-trust/source/anchors/argo_root_cert.pem
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

Thanks to https://github.com/PacktPublishing/Demystifying-Cryptography-with-OpenSSL-3/tree/main/Chapter12/mini-ca
and https://www.devdungeon.com/content/how-add-trusted-ca-certificate-centosfedora
