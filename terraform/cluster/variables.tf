variable "client_id" {
  description = "The client ID for the Azure Service Principal"
  type        = string
  default     = ""
}

variable "client_secret" {
  description = "The client secret for the Azure Service Principal"
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "The tenant ID for the Azure subscription"
  type        = string
  default     = ""
}

variable "subscription_id" {
  description = "The subscription ID for the Azure account"
  type        = string
  default     = ""
}
