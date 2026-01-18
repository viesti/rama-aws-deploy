###
# variables & configuration
###

## Required vars

variable "region" { type = string }

variable "cluster_name" { type = string } # from rama-cluster.sh
variable "key_name" { type = string }     # from ~/.rama/auth.tfvars

# From rama.tfvars
variable "username" { type = string }

variable "rama_source_path" { type = string }
variable "license_source_path" {
  type    = string
  default = ""
}
variable "zookeeper_url" { type = string }

variable "conductor_ami_id" { type = string }
variable "supervisor_ami_id" { type = string }
variable "zookeeper_ami_id" { type = string }

variable "zookeeper_instance_type" { type = string }
variable "conductor_instance_type" { type = string }
variable "supervisor_instance_type" { type = string }

variable "supervisor_num_nodes" { type = number }

## Optional vars

variable "zookeeper_num_nodes" {
  type    = number
  default = 1
}

variable "supervisor_volume_size_gb" {
  type    = number
  default = 100
}

variable "use_private_ip" {
  type    = bool
  default = false
}

variable "private_ssh_key" {
  type    = string
  default = null
}
