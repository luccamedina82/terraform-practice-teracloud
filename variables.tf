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

variable "project_name" {
  type        = string
  description = "Nombre base del proyecto. Participa en el nombre de todos los recursos."
  default     = "tf-workshop"
}

variable "name_suffix" {
  type        = string
  description = "Sufijo que identifica al autor. Permite que varias personas trabajen en la misma cuenta sin colisionar."
  default     = "lm"
}

variable "vpc_cidr" {
  type        = string
  description = "Rango CIDR de la VPC. /16 da 65.536 direcciones, de sobra para el lab."
  default     = "10.0.0.0/16"
}