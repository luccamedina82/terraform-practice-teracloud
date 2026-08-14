# Diseño en papel — Workshop Terraform en AWS

> Documento de diseño previo a escribir el primer `.tf`. Se completa y corrige durante la
> ejecución; lo que cambie se anota en `BITACORA.md` con el motivo.
>
> Versión: v1 — agosto 2026

---

## 1. Parámetros fijos

| Parámetro | Valor | Nota |
|---|---|---|
| Cuenta AWS | `104981180500` | Cuenta limpia, sin infra de labs anteriores |
| Región | `us-east-1` | El enunciado dice `us-east-2`; se desvía a propósito por continuidad |
| Perfil AWS local | (a definir en Fase 0) | Usuario IAM personal ya configurado en WSL |
| Dominio | `luccamedina.ownboarding.teratest.net` | Hosted zone ya existente, delegada por NS |
| Subdominio del juego | `<juego>.luccamedina.ownboarding.teratest.net` | El `<juego>` se define al elegir la imagen |
| Juego / imagen Docker | (a definir) | Requisito: corre en navegador, puerto conocido |
| Sufijo de nombres | `-lm` | Vía `local.name_suffix`, no hardcodeado |

---

## 2. Estructura de archivos

Terraform concatena **todos** los `.tf` del directorio; el layout no afecta el grafo de
dependencias. La separación es didáctica y de mantenimiento, no funcional.

```
tf-workshop/
├── CLAUDE.md                 # contexto para Claude Code (no es Terraform)
├── DISENO.md                 # este archivo
├── BITACORA.md               # registro para la documentación final
├── .gitignore
├── versions.tf               # required_version + required_providers + backend
├── providers.tf              # provider "aws" con default_tags
├── variables.tf              # inputs
├── terraform.tfvars          # valores (IGNORADO por git)
├── locals.tf                 # nombres derivados
├── data.tf                   # aws_route53_zone + aws_ami
├── network.tf                # vpc, subnets, igw, rt, association, sg + reglas
├── ecr.tf                    # repositorio
├── iam.tf                    # role, attachments, instance profile
├── compute.tf                # aws_instance
├── dns.tf                    # aws_route53_record
├── outputs.tf                # todos los outputs juntos
└── scripts/
    └── user-data.sh.tftpl    # plantilla de user_data
```

---

## 3. Inventario de recursos

### Data sources (Paso 1) — leen, no crean

| Referencia | Recurso | Filtro clave |
|---|---|---|
| `data.aws_route53_zone.main` | `aws_route53_zone` | `name` = dominio, `private_zone = false` |
| `data.aws_ami.al2023` | `aws_ami` | `most_recent = true`, `owners = ["amazon"]`, filtro por nombre AL2023 x86_64 |

### Recursos creados

| # | Recurso Terraform | Nombre (tag Name) | Config clave |
|---|---|---|---|
| 1 | `aws_vpc.main` | `vpc-tf-workshop-lm` | `10.0.0.0/16`, `enable_dns_hostnames = true` |
| 2 | `aws_subnet.public` | `subnet-public-tf-workshop-lm` | `10.0.1.0/24`, `us-east-1a`, `map_public_ip_on_launch = true` |
| 3 | `aws_subnet.private` | `subnet-private-tf-workshop-lm` | `10.0.2.0/24`, `us-east-1b`, sin ruta a internet |
| 4 | `aws_internet_gateway.main` | `igw-tf-workshop-lm` | Attached a la VPC |
| 5 | `aws_route_table.public` | `rt-public-tf-workshop-lm` | `0.0.0.0/0` → IGW |
| 6 | `aws_route_table_association.public` | — | Solo la subnet pública |
| 7 | `aws_security_group.instance` | `sg-instance-tf-workshop-lm` | Sin reglas inline |
| 8 | `aws_vpc_security_group_ingress_rule.http` | — | TCP 80 desde `0.0.0.0/0` |
| 9 | `aws_vpc_security_group_ingress_rule.app` | — | TCP 8080 desde `0.0.0.0/0` |
| 10 | `aws_vpc_security_group_egress_rule.all` | — | Todo el tráfico saliente |
| 11 | `aws_ecr_repository.game` | `<juego>-tf-workshop-lm` | `scan_on_push = true`, `force_delete = true` |
| 12 | `aws_iam_role.instance` | `role-ec2-tf-workshop-lm` | Trust policy: `ec2.amazonaws.com` |
| 13 | `aws_iam_role_policy_attachment.ecr` | — | `AmazonEC2ContainerRegistryReadOnly` |
| 14 | `aws_iam_role_policy_attachment.ssm` | — | `AmazonSSMManagedInstanceCore` |
| 15 | `aws_iam_instance_profile.instance` | `profile-ec2-tf-workshop-lm` | Envuelve el rol |
| 16 | `aws_instance.game` | `ec2-tf-workshop-lm` | `t3.micro`, subnet pública, user_data |
| 17 | `aws_route53_record.game` | `<juego>.<dominio>` | Tipo A, TTL 300, IP pública de la EC2 |

**Fuera de Terraform (creado por CLI en Fase 0):** bucket S3 de estado, con versioning +
encryption + block public access. No se administra por Terraform para evitar el problema del
huevo y la gallina (el backend lo necesita existente antes del `init`).

### Outputs

| Output | Valor | Para qué |
|---|---|---|
| `vpc_id` | `aws_vpc.main.id` | Verificación de Fase 2 |
| `ecr_repository_url` | `aws_ecr_repository.game.repository_url` | Se usa a mano en el push de la imagen |
| `instance_public_ip` | `aws_instance.game.public_ip` | Verificación y `ssm start-session` |
| `instance_id` | `aws_instance.game.id` | Para Session Manager |
| `game_url` | URL completa | Entregable final |

---

## 4. Grafo de dependencias

Terraform lo deriva solo de las referencias entre recursos. Escrito a mano para poder
contrastarlo contra la salida real de `terraform plan`:

```
data.aws_route53_zone.main ─────────────────────────────┐
data.aws_ami.al2023 ──────────────────────┐             │
                                          │             │
aws_vpc.main                              │             │
  ├── aws_subnet.public ──────────────┐   │             │
  ├── aws_subnet.private              │   │             │
  ├── aws_internet_gateway.main ──┐   │   │             │
  ├── aws_security_group.instance  │   │   │             │
  │     ├── ingress.http           │   │   │             │
  │     ├── ingress.app            │   │   │             │
  │     └── egress.all             │   │   │             │
  └── aws_route_table.public ◄─────┘   │   │             │
        └── aws_route_table_association ┘   │             │
                                          │             │
aws_ecr_repository.game ──────────────┐   │             │
                                      │   │             │
aws_iam_role.instance                 │   │             │
  ├── attachment.ecr                  │   │             │
  ├── attachment.ssm                  │   │             │
  └── aws_iam_instance_profile ───┐   │   │             │
                                  │   │   │             │
                    aws_instance.game ◄───┘             │
                      (subnet + sg + profile + ami +    │
                       ecr_url en user_data)            │
                          │                             │
                          └──► aws_route53_record.game ◄┘
```

**Dependencia no obvia:** el `user_data` interpola `aws_ecr_repository.game.repository_url`,
así que la instancia depende del ECR aunque no haya ningún argumento directo que los una.
Es una dependencia implícita creada por la plantilla.

---

## 5. Decisiones tomadas antes de escribir código

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Archivos separados por dominio | `main.tf` monolítico | Didáctico: demuestra que el orden de archivos es irrelevante para el grafo |
| `default_tags` en el provider | Tag por recurso | Una sola definición, imposible olvidarse |
| Nombres vía `local` derivado de variables | String repetido | Cambiar el proyecto es cambiar una variable |
| `aws_vpc_security_group_ingress_rule` (recursos separados) | Bloques `ingress {}` inline | Diffs quirúrgicos, no borra reglas externas, dirección del provider v6 |
| `templatefile()` a `scripts/user-data.sh.tftpl` | Heredoc inline | Script lintable, HCL limpio, obliga a interpolar región y URL de ECR |
| Backend local primero, migrar a S3 en Fase 3 | S3 desde el inicio | Ver el estado local y la migración en vivo es el punto del ejercicio |
| Bucket de estado creado por CLI | Creado por Terraform | Huevo y gallina con el backend |
| `us-east-1` | `us-east-2` del enunciado | Continuidad con la hosted zone y con todo lo anterior |
| `force_delete = true` en ECR | Default | Sin esto, `terraform destroy` falla si hay imágenes |

---

## 6. Puntos de riesgo identificados antes de empezar

| Riesgo | Detalle | Mitigación planificada |
|---|---|---|
| Puerto 80 vs 8080 | El SG abre 80 pero `docker run -p 8080:8080` no escucha ahí | Mapear `-p 80:<puerto_app>`; dejar 8080 abierto para debug |
| `amazon-ssm-agent` en AL2023 | Si el paquete no existe, `yum install` falla y **tampoco instala Docker** | Verificar antes; separar en dos `yum install`; agregar logging al script |
| IP pública sin EIP | El registro A queda apuntando a una IP que cambia con stop/start | Documentar como decisión lab vs. prod |
| `terraform destroy` en ECR | Repo con imágenes no se borra | `force_delete = true` desde el inicio |
| Permisos IAM del usuario | Crear roles/instance profiles requiere permisos que suelen faltar | Verificar en Fase 0, no en Fase 5 |
| `.terraform.lock.hcl` en `.gitignore` | El enunciado lo ignora; HashiCorp recomienda commitearlo | Verificar contra doc oficial y documentar la divergencia |
| `AdministratorAccess` + access keys | Contradice el criterio de OIDC del Workshop 5 | Fila de la tabla lab vs. prod |
| Subnet privada sin uso | No la consume ningún recurso | Anotado: existe solo para contrastar route tables |

---

## 7. Fases de ejecución (validación incremental)

| Fase | Alcance | Criterio de salida |
|---|---|---|
| 0 | Instalación, perfil, bucket S3, repo, `.gitignore`, `versions.tf` + `providers.tf` | `terraform init` OK · `plan` dice "no changes" · `sts get-caller-identity` OK |
| 1 | `data.tf` + outputs | `apply` no crea nada e imprime zone ID y AMI ID |
| 2 | `network.tf` | `plan` muestra los recursos esperados y en el orden esperado · `apply` OK |
| 3 | Migración a backend S3 | `.tfstate` local vacío, objeto presente y versionado en S3 |
| 4 | `ecr.tf` + push manual de la imagen | `aws ecr list-images` devuelve el tag |
| 5 | `iam.tf` | `apply` OK, instance profile visible |
| 6 | `compute.tf` + `user-data.sh.tftpl` | Session Manager conecta · `docker ps` · `curl localhost` desde adentro |
| 7 | `dns.tf` | `dig` resuelve · juego carga en el navegador |
| 8 | Drift e import | Cambio manual detectado por `plan -refresh-only` · recurso externo importado sin diff |
| 9 | Cierre | `terraform destroy` deja la cuenta en cero |

---

## 8. Tabla lab vs. producción — v1

Se completa durante la ejecución. Lo que ya se puede anticipar:

| Decisión (lab) | Por qué | En producción |
|---|---|---|
| Usuario IAM con `AdministratorAccess` y access keys estáticas | Lo pide el enunciado | OIDC federation desde CI/CD, sin credenciales estáticas; permisos mínimos por rol |
| Estado en un bucket sin política de acceso restrictiva | Alcance del lab | Bucket dedicado con policy explícita, MFA delete, y roles separados por entorno |
| EC2 en subnet pública con IP pública | Requisito del enunciado (acceso directo por DNS) | Instancia en subnet privada detrás de un ALB; sin IP pública |
| IP pública sin Elastic IP en el registro DNS | Simplicidad | EIP, o mejor un ALB con registro Alias |
| Un solo contenedor en una sola EC2, sin ASG | Alcance del lab | ASG + ALB, o ECS/Fargate — hoy no hay ni alta disponibilidad ni recuperación automática |
| Sin HTTPS (registro A directo a la IP, puerto 80) | El enunciado no lo pide | ACM + ALB con listener 443 y redirect 80→443 |
| SG abierto a `0.0.0.0/0` en 80 y 8080 | Acceso público al juego | Solo 443 desde el ALB; el puerto de la app nunca expuesto a internet |
| `docker pull` en el `user_data`, sin reintento | Simplicidad | Imagen resuelta por el orquestador con política de reintento y health check |
| Push de la imagen a ECR a mano | Es un paso didáctico del enunciado | Pipeline de CI/CD que buildea y pushea con tag = commit SHA |
| Tag `latest` mutable en ECR | Menor fricción | Tag inmutable por SHA, `latest` excluido |
| Un solo estado para toda la infra | Un solo entorno | Estados separados por entorno/capa, con workspaces o directorios |
| Sin módulos | El objetivo es ver los recursos crudos | Módulos reutilizables versionados |
