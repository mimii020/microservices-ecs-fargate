variable "project" {
    type    = string
    default = "microservices-ecs-fargate"
}

variable "vpc_cidr" {
    type    = string
    default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "services" {
  type = map(object({
    port = number
    priority = number
  }))
  default = {
    auth   = { port = 5000, priority = 100 }
    orders = { port = 5001, priority = 200 }
  }
}