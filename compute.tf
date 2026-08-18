resource "aws_instance" "game" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.instance.id]

  # Recibe el NOMBRE del instance profile, no su ARN.
  iam_instance_profile = aws_iam_instance_profile.instance.name

  # La referencia a aws_ecr_repository.game de aca adentro es lo que crea la
  # dependencia implicita con el ECR: no hace falta depends_on.
  # OJO: Terraform sabe que el REPOSITORIO tiene que existir, pero no sabe nada
  # de la imagen adentro. El push sigue siendo un paso manual.
  user_data = templatefile("${path.module}/scripts/user-data.sh.tftpl", {
    region         = var.region
    registry       = split("/", aws_ecr_repository.game.repository_url)[0]
    ecr_url        = aws_ecr_repository.game.repository_url
    image_tag      = var.image_tag
    container_name = var.game_name
    host_port      = var.host_port
    container_port = var.container_port
  })

  # Sin esto, cambiar el script actualiza el atributo en el estado y NO vuelve a
  # ejecutarlo: cloud-init corre el user_data solo en el primer arranque. El
  # apply diria "1 changed" y la instancia seguiria con el script viejo.
  user_data_replace_on_change = true

  # Fuerza IMDSv2. Con el default (optional), un GET sin token devuelve las
  # credenciales del rol: cualquier SSRF en la app se convierte en robo de
  # credenciales.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # encrypted es false por defecto, y el cifrado de EBS no tiene costo extra.
  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true

    tags = {
      Name = "ebs-root-${local.name}"
    }
  }

  tags = {
    Name = "ec2-${local.name}"
  }
}
