# Create the Kubernetes resources for volumes required by the consul helm chart
resource "kubernetes_storage_class" "example" {
  depends_on = [module.eks]

  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"
}

resource "kubernetes_persistent_volume" "efs_pv" {
  count = var.consul_server_nodes

  metadata {
    name = "efs-pv-${count.index}"
  }

  spec {
    capacity = {
      storage = "10Gi"
    }
    volume_mode = "Filesystem"
    access_modes = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Delete"
    storage_class_name = kubernetes_storage_class.example.metadata.0.name

    persistent_volume_source {
      csi {
        driver = "efs.csi.aws.com"
        volume_handle = "${aws_efs_file_system.consul.id}::${aws_efs_access_point.consul_server[count.index].id}"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "consul_server" {
  count = var.consul_server_nodes
  depends_on = [kubernetes_persistent_volume.efs_pv]

  metadata {
    name = "data-default-consul-server-${count.index}"
  }

  spec {
    access_modes = ["ReadWriteMany"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
    
    storage_class_name = kubernetes_storage_class.example.metadata.0.name
  }
}

resource "helm_release" "consul" {
  depends_on = [module.eks, kubernetes_persistent_volume_claim.consul_server]
  name       = "consul"

  repository = "https://helm.releases.hashicorp.com"
  chart      = "consul"

  set {
    name = "global.name"
    value = "consul"
  }
  
  set {
    name = "server.storageClass"
    value = "efs-sc"
  }

  set {
    name = "server.replicas"
    value = var.consul_server_nodes
  }
  
  set {
    name = "clients.enabled"
    value = false
  }
  
  set {
    name = "controller.enabled"
    value = true
  }
}

# Patch the consul controller for fargate
resource "null_resource" "patch_core_consul" {
  depends_on = [helm_release.consul]

  provisioner "local-exec" {
    command = "kubectl patch deployment consul-controller --patch \"$(cat ./controller_patch.yaml)\""

    environment =  {
      "KUBECONFIG" = "./${module.eks.kubeconfig_filename}"
    }
  }
}
