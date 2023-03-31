# CFK to Cloud Hybrid Architecture Run Book

## Description

This repo contains a detailed run book for setting up a hybrid architecture replicating topics and Schemas from CFK to Confluent Cloud.

> Note: As sandbox environment we will use an AKS Kubernetes Cluster but all confluent related resources remains the same on any other Kubernetes distribution

## Architectural Pattern

![design](./assets/CFK%20Hybrid.png)

## Initial Considerations

There are some requisites to be able to use `Cluster Linking` and `Schema Linking` capabilities:

* The destination CCLoud cluster should be a `dedicated` one.
* For Kafka version on Source Cluster should be 2.4+ for Apache Kafka distributions or 7.0 for CFK/CP

Since CFK Cluster is a stateful infrastructure it's need to be deployed as a statefulset so the recommendation is to setup a `storage class` which has to meet some configuration requirements:

```yml
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

read the [offical CFK docs](https://docs.confluent.io/operator/current/co-storage.html#use-default-kubernetes-storageclass-for-dynamic-provisioning) regarding persistence requirements.

## Platform Settings

### Basic

On this scenario we will cover:

* A basic non secure CFK deployment without any external access (meaning access from outside of the K8s cluster)
* Schema Exporter enable for Schema Registry
* Configure CFK and CCloud Rest Classes to enable Cluster Linking

### 1. Secrets

Since our basic CFK cluster hasn't any security requirement the only secrets we will need to create will be the required ones to establish connection with `Confluent Cloud`.

Basically we will be using 2 different kinds of API Keys, `Cluster` and `Schema Registry`, you need to be sure that the associated `Service Account` has the correct permission on the cluster and schemas.

Read more about Confluent Cloud RBAC Roles [here](https://docs.confluent.io/cloud/current/access-management/access-control/cloud-rbac.html#use-role-based-access-control-rbac-in-ccloud)

Cluster related RBAC Considerations [here](https://docs.confluent.io/cloud/current/access-management/access-control/acl.html#acl-resources-and-operations-available-in-ccloud)

Schema Registry permissions [here](https://docs.confluent.io/cloud/current/sr/schemas-manage.html#access-control-rbac-for-sr-ccloud)

On our use case we will need 4 different kinds of authentication, with their specific secret creation needs:

1. **Basic Authentication**: User/Password authentication used for kafka rest classes and Schema Registry. To create it we will need to create a generic secret from file:

So you need to create a basic.txt file as follow:

```txt
username=<CCLOUD CLUSTER/SR API KEY>
password=<CCLOUD CLUSTER/SR API SECRET>
```

```bash
kubectl -n confluent create secret generic restclass-ccloud --from-file ${DIR}/basic.txt
```

```bash
kubectl -n confluent create secret generic ccloud-sr-credentials --from-file ${DIR}/basic.txt
```

2. **Password Encoder**: Secret needed to encrypt/decrypt passwords sent between brokers and schema registry (and in general within the entire Confluent Platform). This secret is created again from a text file:

```txt
password=<current secret>
oldPassword=<old secret>
```

```bash
kubectl create secret generic password-encoder-secret --from-file ${DIR}/password-encoder.txt
```

3. **Jaas Config**: Needed for authenticate with Confluent Cloud during the `destination linkmode` configuration on the `Source initiated Cluster link`. This is another file based secret as follow:

```properties
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<CCLOUD CLUSTER API KEY>" password="<CCLOUD CLUSTER API SECRET>";
```

4. **TLS Secret**: Needed for TLS handshake with CCloud Cluster during the `destination linkmode` of `clusterlink`.

```bash
kubectl -n confluent create secret generic ccloud-tls-certs --from-file=${DIR}/fullchain.pem --from-file=${DIR}/cacerts.pem
```

to obtain the pem files needed just run:

```bash
openssl s_client -showcerts -servername <CCLOUD SERVER DNS> -connect <CCLOUD SERVER DNS>:443 < /dev/null
```

Where the first certificate showed in console will be the `fullchain`and the second one `cacerts`.

to get the cluster dns just go to the ui or run:

```bash
confluent kafka cluster describe
```

make sure that you are using the proper environment and cluster.

5. **Control Center Basic Authentication secret**: Since Control Center UI that can manage all your cluster, event on this basic setup,  take in count that **at least** you should implement a `basic user/password` authentication. 

You will need to set up a `Kubernetes secret`containing the user, password and role (this one should match with the ones declared on the Control Center CR) of the users you want to gran access to Control Center UI.

In order to do that you need to setup a text file looking like this:

```txt
c3admin: password1,Administrators
c3restricted: password2,Restricted
```

and create the proper secret from this file:

```bash
kubectl -n confluent create secret generic c3-basic-secret --from-file ${DIR}/basic.txt
```

On this basic deployment all components are not exposed to external access so if you need to access to a specfic one you will need to port-forward the pod in which it's running. Take Control Center as example:

```bash
kubectl port-forward controlcenter-0 9021:9021
```

> NOTES:
> filenames are mandatory to be as we show in the document if not it will fail on runtime
> Under `confluent/secrets` folder you will find several sh scripts that you can use to create the secrets described

### CFK Platform

Under `confluent/cluster/basic` folder you can find the K8s CRs for each component on the platform as the `Kafka Rest Class` ones for CFK itself and the one used to connect to Confluent Cloud cluster during the Cluster Link.

You can apply all at once just running (from repo root folder):

```bash
kubectl apply -f confluent/.
```

but to avoid temporary dependency errors and be able to check the health status of each component my recommendation is apply one by one using the following order:

1. Zookeeper
2. Kafka
3. Kafka Rest Classes
4. Schema Registry
5. Kafka Connect
6. KSQL
7. Control Center

you just need to run:

```bash
kubectl apply -f confluent/<CR_FILENAME>
```

#### Specific considerations

As good practice you should be using a specfic storage class configured with following the recommentations already mentioned:

```yaml
  storageClass:
    name: cfk-sc
```

To be able to enable the `schema exporter` schema registry's capabilities you need to use the ``password encoder` secret on your kafka deployment:

```yml
  passwordEncoder:
    secretRef: password-encoder-secret
```

`CCloud Rest class` points to CCLOUD rest endpoint and uses basic auth:

```yml
  kafkaRest:
    endpoint: <CCLOUD Kafka Cluster Rest Endpoint> 
    kafkaClusterID: <Kafka cluster ID>
    authentication:
      type: basic
      basic:
        secretRef: restclass-ccloud
```

On `Schema Registry` side we will need to enable `schema exporter` and use of the `password enconder` field with the same secret used on kafka cluster side:

```yml
  enableSchemaExporter: true
  passwordEncoder:
    secretRef: password-encoder-secret
```

### CFK Resources

With CFK we are able to create platform resources such as `topics` or `schemas` both on the **local DC** and the **CCloud** one under `confluent/resources` folder you can find some examples.

### Synchronizing Data to the Cloud Cluster

To be able to synchronize data from local dc cluster to confluent cloud we will need 2 extra resources:

#### Mirror Topics

> Mirror topics are the building blocks for moving data with Cluster Linking. They are read-only topics that are created and owned by a cluster link.

In order to create  this resource on the CCloud Cluster we will need to create a `ClusterLink` resource. This one can be:

##### Initiated on Destination (Confluent Cloud)

* Created directly on any of Confluent Cloud UI or CLI [here](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/cluster-links-cc.html#requirements-to-create-a-cluster-link))
* Using a CFK CRD like the one described [here](https://github.com/confluentinc/confluent-kubernetes-examples/blob/master/hybrid/clusterlink/ccloud-as-destination-cluster/clusterlink-ccloud.yaml).

On this case Confluent Cloud Cluster owns the cluster link object and will be in charge of consume from the source topic.

As you can see using this option both direction connectivity between Confluent Cloud and CFK cluster must be granted.

##### Source Initiated Cluster Link

Created using a CFK CRD. On this case CFK Cluster owns and manage the entire Cluster Link object and will **push** the information to the CCloud Cluster.

In order to keep the state and the health status on the Cloud side both sides need to be aware of the existence of the resource so you will need to create the both direction linking resources as you can find on `confluent/link/cluster-link-src.yml`.

For further reading go to Source Initiated Cluster Link Docs on [Confluent Website](https://docs.confluent.io/platform/current/multi-dc-deployments/cluster-linking/hybrid-cp.html#hybrid-cloud-and-bridge-to-cloud)
