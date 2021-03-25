# AWS EKS Fargate With Consul Service Mesh Example

### Creates:

* EKS Cluster with Fargate Profile
* Security Groups and Subnets
* EFS Volumes and Access Points for Consul
* Kubernetes Volumes and Claims using EFS for Consul
* Consul Service Mesh via Helm Chart

## Install Terraform 1.13

https://releases.hashicorp.com

You will also need to set your AWS credentials for Terraform

https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication

## Install aws-iam-authenticator

To use `kubectl` you need to install the aws-iam-authenticator to authenticate with the cluster.

https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html

```shell
curl -o aws-iam-authenticator https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.9/2020-11-02/bin/linux/amd64/aws-iam-authenticator
chmod +x ./aws-iam-authenticator
sudo mv ./aws-iam-authenticator /usr/local/bin
```

## Creating the cluster and installing consul

To use terraform to create the cluster run the following command

```shell
terraform init
terraform apply
```

## Patching Consul Controller

After the everything has been created you need the Consul controller to remove the reliance on the Daemonsets. This patch is automatically
applied but requires `kbuectl` to be present in your executable path.

## Patching CoreDNS

After the cluster has been created core dns is automatically patched, this requires `kubectl` to be
present in your executable path

## Using kubectl

A Kubernetes config file that can be used for authentication with the cluster can be obtained from the outputs:

```shell
terraform output kubectl_config > kubeconfig.yaml

export KUBECONFIG=$PWD/kubeconfig.yaml

kubectl get pods
```

## Running applications

Unfortunately due to the unavailability of Daemonsets on EKS Fargate, the mutating webhook responsible
for injecting the data plane components needed by your pod to be part of the service mesh does not currently
work on EKS Fargate. HashiCorp's are working on officially supporting Fargate but until this is released you
need to manually inject the service mesh pods.

To perform this task you can use the unofficial [EKS Fargate Consul Sidecar Injector](https://github.com/nicholasjackson/consul-fargate-injection).

The releases in the consul-fargate-injection repository contain a binary that can mutate a Kubernetes pod deployment YAML file and automatically
append the required items for Consul service mesh. Download the version for your operating system and ensure it is executable.

https://github.com/nicholasjackson/consul-fargate-injection/releases

Once installed you can use the binary to modify your deployments, let's modify the example deployment `api.yaml` in the `app` folder to see 
how this works.  The file `api.yaml` is a standard Kubernetes deployment as show in the following output:

```yaml
---
# API service version 1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  labels:
    app: api
spec:
  replicas: 3
  # Ensure rolling deploys
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
        metrics: enabled
    spec:
      containers:
      - name: api
        image: nicholasjackson/fake-service:v0.20.0
        ports:
        - containerPort: 9090
        env:
        - name: "LISTEN_ADDR"
          value: "127.0.0.1:9090"
        - name: "NAME"
          value: "api"
        - name: "MESSAGE"
          value: "Response from API"

```

This will create 3 instances of the API service, to inject the consul sidecars you run the following command.

```
consul-inject -deployment ./app/api.yaml -service api -port 9090 > ./app/api-with-sidecars.yaml
```

The consul-inject tool requires a number of parameters the first is `-deployment`, this is the name of the Kubernetes deployment that will be
mutated. Next you have `-service api`, this flag registers the name of the service `api` for your application in Consul. The `-port 9090` flag tells
Consul which port your application is listening on, the injected envoy proxy uses this information to send any requests destined for your service.
Finally you pipe the output to a new file `> ./app/api-with-sidecars.yml`. The file that will be created after running this command looks like the following
example. You will see the additional sidecar containers and configuration that are required by Consul service mesh have automatically been added to the deployment.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: api
  name: api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
        metrics: enabled
    spec:
      containers:
      - env:
        - name: LISTEN_ADDR
          value: 127.0.0.1:9090
        - name: NAME
          value: api
        - name: MESSAGE
          value: Response from API
        image: nicholasjackson/fake-service:v0.20.0
        name: api
        ports:
        - containerPort: 9090
      - command:
        - /bin/sh
        - -ec
        - |
          exec /bin/consul agent \
            -node="${HOSTNAME}" \
            -advertise="${POD_IP}" \
            -bind=0.0.0.0 \
            -client=0.0.0.0 \
            -hcl='leave_on_terminate = true' \
            -hcl='ports { grpc = 8502 }' \
            -config-dir=/consul/config \
            -datacenter=dc1 \
            -data-dir=/consul/data \
            -retry-join="${CONSUL_SVC_ADDRESS}" \
            -domain=consul
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: status.podIP
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: CONSUL_SVC_ADDRESS
          value: consul-server.default.svc:8301
        - name: SERVICE_NAME
          value: 'api'
        - name: SERVICE_PORT
          value: '9090'
        image: hashicorp/consul:1.9.1
        imagePullPolicy: IfNotPresent
        name: consul-agent
        ports:
        - containerPort: 8500
          name: http
          protocol: TCP
        - containerPort: 8502
          name: grpc
          protocol: TCP
        - containerPort: 8301
          name: serflan-tcp
          protocol: TCP
        - containerPort: 8301
          name: serflan-udp
          protocol: UDP
        - containerPort: 8600
          name: dns-tcp
          protocol: TCP
        - containerPort: 8600
          name: dns-udp
          protocol: UDP
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -ec
            - |
              curl http://127.0.0.1:8500/v1/status/leader \
              2>/dev/null | grep -E '".+"'
          failureThreshold: 3
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 1
        resources:
          limits:
            cpu: 100m
            memory: 100Mi
          requests:
            cpu: 100m
            memory: 100Mi
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        volumeMounts:
        - mountPath: /consul/data
          name: consul-agent-data
        - mountPath: /consul/config
          name: consul-connect-config-data
        - mountPath: /consul/envoy
          name: consul-connect-envoy-data
      - command:
        - /bin/sh
        - -ec
        - |
          /consul/bin/consul connect envoy \
          -proxy-id="${SERVICE_NAME}-sidecar-proxy-${POD_NAME}" \
          -bootstrap > /consul/envoy/envoy-bootstrap.yaml
          envoy \
          --config-path \
          /consul/envoy/envoy-bootstrap.yaml
        env:
        - name: CONSUL_HTTP_ADDR
          value: http://localhost:8500
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: SERVICE_NAME
          value: 'api'
        image: envoyproxy/envoy-alpine:v1.16.0
        imagePullPolicy: IfNotPresent
        name: consul-connect-envoy-sidecar
        resources: {}
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        volumeMounts:
        - mountPath: /consul/envoy
          name: consul-connect-envoy-data
        - mountPath: /consul/bin
          name: consul-connect-bin-data
      initContainers:
      - command:
        - /bin/sh
        - -ec
        - |
          # Create the service definition
          # the consul agent will automatically read this config and register the service
          # and de-register it on exit.

          cat <<EOF >/consul/config/service.hcl
          services {
            id   = "${SERVICE_NAME}-${POD_NAME}"
            name = "${SERVICE_NAME}"
            address = "${POD_IP}"
            port = ${SERVICE_PORT}
            tags = ["v1"]
            meta = {
              pod-name = "${POD_NAME}"
            }
          }
          services {
            id   = "${SERVICE_NAME}-sidecar-proxy-${POD_NAME}"
            name = "${SERVICE_NAME}-sidecar-proxy"
            kind = "connect-proxy"
            address = "${POD_IP}"
            port = 20000
            tags = ["v1"]
            meta = {
              pod-name = "${POD_NAME}"
            }

            proxy {
              destination_service_name = "${SERVICE_NAME}"
              destination_service_id = "${SERVICE_NAME}-${POD_NAME}"
              local_service_address = "127.0.0.1"
              local_service_port = ${SERVICE_PORT}

            }

            checks {
              name = "Proxy Public Listener"
              tcp = "${POD_IP}:20000"
              interval = "10s"
              deregister_critical_service_after = "10m"
            }

            checks {
              name = "Destination Alias"
              alias_service = "${SERVICE_NAME}-${POD_NAME}"
            }

          }
          EOF

          # Copy the Consul binary
          cp /bin/consul /consul/bin/consul
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: status.podIP
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: SERVICE_NAME
          value: 'api'
        - name: SERVICE_PORT
          value: '9090'
        image: hashicorp/consul:1.9.1
        imagePullPolicy: IfNotPresent
        name: consul-init
        volumeMounts:
        - mountPath: /consul/config
          name: consul-connect-config-data
        - mountPath: /consul/bin
          name: consul-connect-bin-data
      volumes:
      - emptyDir: {}
        name: consul-connect-envoy-data
      - emptyDir: {}
        name: consul-connect-config-data
      - emptyDir: {}
        name: consul-connect-bin-data
      - emptyDir: {}
        name: consul-agent-data
```

Let`s now deploy this application:

```shell
kubectl -f ./app/api-with-sidecar.yaml
```

If you query the cluster you will see the pods starting.

```shell
➜ k get pods
NAME                   READY   STATUS    RESTARTS   AGE
api-86bf9567b6-2ml8s   0/3     Pending   0          4s
api-86bf9567b6-n5k7j   0/3     Pending   0          4s
api-86bf9567b6-w6kxd   0/3     Pending   0          4s
consul-server-0        1/1     Running   0          7m25s
consul-server-1        1/1     Running   0          7m23s
consul-server-2        1/1     Running   0          7m21s
```

Once the pods are running let's take a look at the Consul UI, you will be able to see the service `api` registered successfully along
with the instances for each pod.

![](images/eks_consul_1.png)

Let's now deploy the `web` application that will connect to the API service, again you can run the `consul-injector` command.
The command is very similar to last time you ran it, this time you set the service name to `web` and you are also adding `upstreams`. 
The upstream flag configures consul to expose the service `api` on `localhost` at port `9091`. This is the same convention you 
would use if you were configuring the service using the injector annotations. 

The example application you are deploying is a microservice that has been configured to call the upstream service `API` everytime 
it receives a request. The call to `API` uses the service mesh upstream that you configured using the `upstreams` flag.

Let's generate the file: 

```shell
consul-inject -deployment ./app/web.yaml -service web -port 9090 -upstreams api:9091 > ./app/web-with-sidecar.yaml
```

And apply it using `kubectl`:

```shell
kubectl apply -f ./app/web-with-sidecar.yaml
```

Once all of the pods are running, if you look at Consul you will see three services registered.

![](images/eks_consul_2.png)

If you click on the Nodes tab in Consul, you will also see that there is a node registered for each of the
pods.

![](images/eks_consul_3.png)

Let's test the application, the `web` application does not have a public service created for it however you can use `kubectl port-forward`
to expose a port locally. Run the following command in your terminal.

```shell
kubectl port-forward deployment/web 9090
```

```shell
Forwarding from 127.0.0.1:9090 -> 9090
Forwarding from [::1]:9090 -> 9090
```

You can then curl the endpoint of the service:

```shell
curl http://localhost:9090
```

You should see a response similar to the below, if you look at the `upstream_calls` section
you will see the upstream request to the `api` that was made over the service mesh. If you run
this curl a few times you will see the `ip_addresses` of the upstream change as the service mesh
loadbalances your requests.

```json
{
  "name": "web",
  "uri": "/",
  "type": "HTTP",
  "ip_addresses": [
    "172.16.2.170"
  ],
  "start_time": "2021-03-24T17:06:47.857197",
  "end_time": "2021-03-24T17:06:47.916345",
  "duration": "59.148263ms",
  "body": "Response from Web",
  "upstream_calls": {
    "http://localhost:9091": {
      "name": "api",
      "uri": "http://localhost:9091",
      "type": "HTTP",
      "ip_addresses": [
        "172.16.2.232"
      ],
      "start_time": "2021-03-24T17:06:47.915251",
      "end_time": "2021-03-24T17:06:47.915473",
      "duration": "221.564µs",
      "headers": {
        "Content-Length": "260",
        "Content-Type": "text/plain; charset=utf-8",
        "Date": "Wed, 24 Mar 2021 17:06:47 GMT"
      },
      "body": "Response from API",
      "code": 200
    }
  },
  "code": 200
}
```

## Destroying the demo

Running resources cost money so do not forget to tear down your cluster, you can run the `terraform destroy` command to remove 
all the resources you have created.

```shell
terraform destroy
```
