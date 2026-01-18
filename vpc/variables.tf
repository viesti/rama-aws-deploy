variable "res_prefix" {
  type        = string
  description = "Resource name prefix, for example name of the cluster"
}

variable public-subnet-count {
  default = 1
}

variable private-subnet-count {
  default = 1
}

variable bastion_key_name {}
