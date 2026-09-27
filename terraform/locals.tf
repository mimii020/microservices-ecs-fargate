locals {
  azs = {
    for idx, name in slice(data.aws_availability_zones.available.names, 0, var.az_count) :
    name => idx
  }
  az_names = slice(data.aws_availability_zones.available.names, 0, var.az_count)  
}

locals {
  ecr_registry_path = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

locals { db_username = "dbadmin" }

locals {
  interface_endpoints = {
    ecr_api        = "ecr.api"
    ecr_dkr        = "ecr.dkr"
    secretsmanager = "secretsmanager"
    logs           = "logs"
  }
}