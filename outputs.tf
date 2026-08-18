output "main_route53_zone_id" {
  value       = data.aws_route53_zone.main.zone_id
  description = "ID de la hosted zone publica del dominio. Lo consume aws_route53_record en la Fase 7 para crear el registro A del juego."
}

output "main_route53_zone_name" {
  value       = data.aws_route53_zone.main.name
  description = "Nombre de la zona tal como lo devuelve Route53, con punto final. Sirve para confirmar que el data source apunto a la zona esperada y no a otra."
}

output "main_route53_zone_arn" {
  value       = data.aws_route53_zone.main.arn
  description = "ARN de la hosted zone. Trazabilidad para la documentacion final: identifica la zona sin ambiguedad, incluida la cuenta."
}

output "al2023_ami_id" {
  value       = data.aws_ami.al2023.id
  description = "ID de la AMI de Amazon Linux 2023 x86_64 (linea kernel-6.1) que usara aws_instance en la Fase 6. Cambia cuando AWS publica un build nuevo de esa linea."
}

output "al2023_ami_name" {
  value       = data.aws_ami.al2023.name
  description = "Nombre completo de la AMI resuelta. El ID solo no es legible: este campo dice que build y que linea de kernel se selecciono, y es lo que va a la tabla de trazabilidad de la documentacion final."
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID de la VPC del workshop. Criterio de salida de la Fase 2 y filtro para verificar por CLI el resto de los recursos de red."
}

output "public_subnet_id" {
  value       = aws_subnet.public.id
  description = "ID de la subnet publica. La consume aws_instance en la Fase 6."
}

output "private_subnet_id" {
  value       = aws_subnet.private.id
  description = "ID de la subnet privada. No la consume ningun recurso: existe para contrastar el efecto de la route table."
}

output "instance_security_group_id" {
  value       = aws_security_group.instance.id
  description = "ID del security group de la instancia. Lo consume aws_instance en la Fase 6 y sirve para verificar las reglas por CLI."
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.game.repository_url
  description = "URL del repositorio ECR, con formato <account>.dkr.ecr.<region>.amazonaws.com/<repo>. Se usa a mano en el docker tag y el docker push de la Fase 4, y la interpola el user_data de la Fase 6."
}
