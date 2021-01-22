# AWS Terraform Fargate Example

### Creates:

* EKS Cluster with Fargate Profile
* Security Groups and Subnets
* RDS Maria DB instance
* Nginx Pod
* Load balancer for Pod

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

## Using kubectl

A Kubernetes config file that can be used for authentication with the cluster can be obtained from the outputs:

```shell
terraform output kubectl_config > kubeconfig.yaml

export KUBECONFIG=$PWD/kubeconfig.yaml

kubectl get pods
```
