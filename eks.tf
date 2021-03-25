module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "13.2.1"
  
  cluster_name    = local.cluster_name
  cluster_version = "1.18"
  subnets         = module.vpc.private_subnets

  tags = {
    Environment = "test"
    GithubRepo  = "terraform-aws-eks"
    GithubOrg   = "terraform-aws-modules"
  }

  vpc_id = module.vpc.vpc_id

  fargate_profiles = {
    default = {
      namespace = "default"
    }
  
    system = {
      namespace = "kube-system"
    }
  }

  map_roles    = var.map_roles
  map_users    = var.map_users
  map_accounts = var.map_accounts

  cluster_delete_timeout = "1h"
}

# patch core dns
resource "null_resource" "patch_core_dns" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = "kubectl patch deployment coredns -n kube-system --type json -p='[{\"op\": \"remove\", \"path\": \"/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type\"}]'"

    environment =  {
      "KUBECONFIG" = "./${module.eks.kubeconfig_filename}"
    }
  }
}
