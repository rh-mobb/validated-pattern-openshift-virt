variable "platform_json" {
  description = "Path to installer clusters/<name>/platform.json (make cluster.<name>.platform)."
  type        = string
}

variable "pool_size_tib" {
  type    = number
  default = 1
}

variable "custom_throughput_mibps" {
  description = "Flexible + Manual QoS pool throughput. Azure minimum is 128 MiB/s."
  type        = number
  default     = 128
}

variable "tags" {
  type    = map(string)
  default = {}
}
