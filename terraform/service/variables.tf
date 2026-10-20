variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "service_name" { type = string }

variable "image" {
  description = "Digest-pinned image reference. Supplied by the pipeline (-var), never stored in tfvars."
  type        = string
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "timeout_seconds" {
  type    = number
  default = 30
}

variable "max_concurrency" {
  type    = number
  default = 80
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 3
}

variable "ingress" {
  type    = string
  default = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
}

variable "invoker_members" {
  type    = list(string)
  default = []
}

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "secret_env" {
  type = map(object({
    secret  = string
    version = string
  }))
  default = {}
}

variable "deletion_protection" {
  type    = bool
  default = true
}
