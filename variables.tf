variable "region" {
  type        = string
  description = "The AWS region to deploy the resources in"
  default     = "us-east-1"
}


variable "default_tags" {
  type        = map(string)
  description = "Etiquetas por defecto aplicadas a todos los recursos del repositorio"
  default = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Repository  = "terraform-practice-teracloud"
  }
}
