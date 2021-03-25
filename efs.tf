# Create the EFS file system and access points used by the Consul server
resource "aws_efs_file_system" "consul" {
  encrypted                       = true
  performance_mode                = "generalPurpose"
  throughput_mode                 = "bursting"
}

resource "aws_efs_mount_target" "consul" {
  count = length(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.consul.id
  security_groups = [module.eks.cluster_primary_security_group_id]
  subnet_id       = module.vpc.private_subnets[count.index]
}

resource "aws_efs_access_point" "consul_server" {
  count = var.consul_server_nodes
  file_system_id = aws_efs_file_system.consul.id
  
  root_directory {
    path = "/server${count.index}"
    creation_info {
      owner_gid = 1000
      owner_uid = 100
      permissions = "0755"
    }
  }

  posix_user {
    gid = 1000
    uid = 100
  }
}
