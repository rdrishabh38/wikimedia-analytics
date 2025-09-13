variable "cluster_name" {
  description = "The name of the k3d cluster."
  type        = string
}

variable "servers" {
  description = "Number of server nodes."
  type        = number
  default     = 1
}

variable "agents" {
  description = "Number of agent nodes."
  type        = number
  default     = 2
}

variable "host_port" {
  description = "Host port to map to the cluster's ingress."
  type        = string
}
