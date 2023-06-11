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

OK now we can test, let's generate a certificate for localhost with the just added CA.


```shell
cat << EOF > localhost.cnf
[req]
prompt                  = no
distinguished_name      = distinguished_name_server_cert
req_extensions          = v3_server_cert

[distinguished_name_server_cert]
countryName             = FR
stateOrProvinceName     = Paca
localityName            = Trourrettes sur Loup
organizationName        = Minonne
commonName              = localhost

[v3_server_cert]
subjectAltName = DNS:localhost
EOF
```

```shell
openssl genpkey \
    -algorithm ED448 \
    -out localhost-key.pem
```

```shell
openssl req \
    -config localhost.cnf \
    -new \
    -key localhost-key.pem \
    -out localhost-csr.pem \
    -text
```


let's sign it with the intermediate CA


```shell
openssl ca \
    -batch \
    -config ./intermediate/intermediate.cnf \
    -in  ./localhost-csr.pem \
    -out ./localhost-cert.pem
```


and now let's create a test http server on localhost.

```shell
openssl s_server -key localhost-key.pem -cert localhost-cert.pem -accept 5000 -WWW
```

and now in another shell you can connect to the server:

```shell
$ curl https://localhost:5000
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
