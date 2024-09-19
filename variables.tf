# 2. Create Availability Zone
variable "vpc_az" {
  type        = list(string)
  description = "Availability Zones"
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}


# ubuntu = ami-01811d4912b4ccb26