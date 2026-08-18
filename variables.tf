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

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR de la subnet publica. Tiene que estar contenido en vpc_cidr."
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR de la subnet privada. Tiene que estar contenido en vpc_cidr y no solaparse con la publica."
  default     = "10.0.2.0/24"
}

variable "public_subnet_az" {
  type        = string
  description = "Zona de disponibilidad de la subnet publica."
  default     = "us-east-1a"
}

variable "private_subnet_az" {
  type        = string
  description = "Zona de disponibilidad de la subnet privada. Distinta de la publica para mostrar que una subnet vive en una sola AZ."
  default     = "us-east-1b"
}

variable "game_name" {
  type        = string
  description = "Nombre corto del juego. Alimenta el nombre del repositorio ECR y el subdominio del registro DNS. Solo minusculas: ECR rechaza mayusculas en el nombre del repositorio."
  default     = "sf"
}

variable "instance_type" {
  type        = string
  description = "Tipo de instancia EC2. t3.micro alcanza de sobra para un nginx sirviendo archivos estaticos."
  default     = "t3.micro"
}

variable "image_tag" {
  type        = string
  description = "Tag de la imagen en ECR que levanta el user_data. Mutable a proposito en el lab: permite corregir la imagen y volver a pushear sin tocar el HCL."
  default     = "latest"
}

variable "host_port" {
  type        = number
  description = "Puerto del host donde se publica el contenedor. Tiene que coincidir con una regla de ingress del SG."
  default     = 80
}

variable "container_port" {
  type        = number
  description = "Puerto donde escucha el proceso dentro del contenedor. Para la imagen del juego es el 80 de nginx."
  default     = 80
}
