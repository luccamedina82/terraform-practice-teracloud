resource "aws_route53_record" "game" {
  # El ID, no el nombre: Route53 admite dos zonas homonimas (una publica y una
  # privada). El data source de la Fase 1 desambigua con private_zone = false.
  zone_id = data.aws_route53_zone.main.zone_id

  # data.aws_route53_zone.main.name viene con punto final, asi que esto queda
  # como "sf.luccamedina.ownboarding.teratest.net.". Route53 lo normaliza.
  name = "${var.game_name}.${data.aws_route53_zone.main.name}"
  type = "A"

  # Obligatorio para registros no-alias. Corto a proposito: la EC2 no tiene
  # Elastic IP, y un stop/start le cambia la IP publica.
  ttl = 60

  # Esta referencia es la dependencia implicita con la instancia. Si la EC2 se
  # reemplaza, la IP nueva actualiza el registro en el mismo apply.
  records = [aws_instance.game.public_ip]

  # allow_overwrite se deja en su default (false) a proposito: si el registro ya
  # existiera creado a mano, el apply falla en vez de pisarlo.

  # Los registros de Route53 no son taggables: los default_tags del provider no
  # aplican aca. La ausencia de tags no es un olvido.
}
