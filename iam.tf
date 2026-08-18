resource "aws_iam_role" "instance" {
  name        = "role-ec2-${local.name}"
  description = "Rol de la EC2 del juego: lectura de ECR para el docker pull y Session Manager para el acceso"

  # Trust policy: QUIEN puede asumir el rol. Sin esto el rol no se puede usar.
  # El principal es el servicio EC2, no la cuenta ni el usuario IAM.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "role-ec2-${local.name}"
  }
}

# Permite el docker pull del user_data. Incluye ecr:GetAuthorizationToken.
resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Habilita Session Manager. Por esto el SG no abre el 22 ni hace falta key pair.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2 no acepta un rol: acepta un instance profile, que envuelve a uno solo.
# La consola lo crea sin mostrarlo; en Terraform es explicito.
resource "aws_iam_instance_profile" "instance" {
  name = "profile-ec2-${local.name}"
  role = aws_iam_role.instance.name

  tags = {
    Name = "profile-ec2-${local.name}"
  }
}
