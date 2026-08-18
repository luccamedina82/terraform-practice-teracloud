# Bitácora — Workshop Terraform en AWS

> Registro vivo. Se completa durante el trabajo en Claude Code y se lleva de vuelta al chat web
> para generar la documentación con la skill `documentacion-tecnica`.
>
> Las secciones de abajo están alineadas con la estructura que espera esa skill, así que
> completarlas bien acá ahorra reconstruir todo de memoria después.

---

## 1. Recursos creados (trazabilidad)

Completar con IDs reales al cerrar cada fase.

| Recurso | Nombre | ID real | Config clave | ¿Genera costo mientras exista? |
|---|---|---|---|---|
| Hosted zone Route53 (Fase 1, **leída, no creada** — data source) | `luccamedina.ownboarding.teratest.net.` | `Z0909248Q51XTVKXPOG` (ARN `arn:aws:route53:::hostedzone/Z0909248Q51XTVKXPOG`) | `private_zone = false`. Preexistente en la cuenta, delegada por NS | No la creó ni la cobra este lab. La zona en sí cuesta ~0,50 USD/mes pero ya existía |
| AMI Amazon Linux 2023 (Fase 1, **leída, no creada** — data source) | `al2023-ami-2023.12.20260803.3-kernel-6.1-x86_64` | `ami-07a5b367e8dc8bd92` | x86_64 · hvm · ebs · `ena_support` true · `imds_support` v2.0 · `boot_mode` uefi-preferred · owner `137112412989` (alias `amazon`) · **`deprecation_time` 2026-11-01** | No. Es una AMI pública de Amazon |
| Bucket S3 de estado (Fase 0, **fuera de Terraform**, creado por CLI) | `tf-state-workshop-lm-104981180500` | `arn:aws:s3:::tf-state-workshop-lm-104981180500` | `us-east-1` · versioning `Enabled` · SSE-S3 (`AES256`) con `BucketKeyEnabled` · block public access en los 4 flags · tags `Project`/`ManagedBy`/`Purpose` | Sí, pero despreciable: el bucket en sí no cuesta, solo el almacenamiento del `.tfstate` (unos KB) y sus versiones. Del orden de centavos de USD al mes. **No lo borra `terraform destroy`** — hay que eliminarlo a mano en Fase 9 |
| VPC (Fase 2) | `vpc-tf-workshop-lm` | `vpc-09b6544aea696e9dd` | `10.0.0.0/16` · `enable_dns_support` y `enable_dns_hostnames` en `true` · `state: available` | No. Una VPC vacía no factura |
| Subnet pública (Fase 2) | `subnet-public-tf-workshop-lm` | `subnet-0033c17b9c7ec238c` | `10.0.1.0/24` · `us-east-1a` · `map_public_ip_on_launch = true` | No |
| Subnet privada (Fase 2) | `subnet-private-tf-workshop-lm` | `subnet-03eb6819b955061da` | `10.0.2.0/24` · `us-east-1b` · `map_public_ip_on_launch = false` · sin association: cae en la main route table | No |
| Internet Gateway (Fase 2) | `igw-tf-workshop-lm` | `igw-03d79e19ed587867e` | Attachment a `vpc-09b6544aea696e9dd` en estado `available` | No. El IGW es gratis — el que cobra por hora es el NAT Gateway, que este lab no usa |
| Route table pública (Fase 2) | `rt-public-tf-workshop-lm` | `rtb-0e538ac0b28dbd036` | Dos rutas activas: `10.0.0.0/16 → local` (puesta por AWS) y `0.0.0.0/0 → igw-03d79e19ed587867e` (declarada) | No |
| Main route table de la VPC (Fase 2, **creada por AWS, NO administrada por Terraform**) | sin tag `Name` | `rtb-0e10176026f1fca6c` | Única ruta: `10.0.0.0/16 → local`. Es la que hace privada a la subnet privada, por omisión | No |
| Route table association (Fase 2) | — | `rtbassoc-04d172e50037a766b` | Une `subnet-0033c17b9c7ec238c` con `rtb-0e538ac0b28dbd036`. Solo la subnet pública | No |
| Security group (Fase 2) | argumento `name` = `instance-tf-workshop-lm` · tag `Name` = `sg-instance-tf-workshop-lm` | `sg-0b1c39e081bc25b04` | Sin reglas inline. Ver las tres filas siguientes | No |
| Regla ingress HTTP (Fase 2) | `sgr-ingress-http-tf-workshop-lm` | `sgr-00b6e69b2098978b4` | `tcp` 80–80 desde `0.0.0.0/0` | No |
| Regla ingress app (Fase 2) | `sgr-ingress-app-tf-workshop-lm` | `sgr-047ba8d2ffd001523` | `tcp` 8080–8080 desde `0.0.0.0/0`. Solo debug del lab | No |
| Regla egress total (Fase 2) | `sgr-egress-all-tf-workshop-lm` | `sgr-06ba0b4abc932a07f` | `ip_protocol = -1`, `from`/`to` = `-1`, hacia `0.0.0.0/0` | No |
| Repositorio ECR (Fase 4) | argumento `name` = `sf-tf-workshop-lm` · tag `Name` = `ecr-sf-tf-workshop-lm` | `104981180500.dkr.ecr.us-east-1.amazonaws.com/sf-tf-workshop-lm` | `MUTABLE` · `scanOnPush = true` · `force_delete = true` · cifrado `AES256` (default, no declarado) · creado `2026-08-18T12:46:16Z` | Sí: se cobra el almacenamiento de las imágenes. 33 MiB es despreciable, pero **el repo sí lo borra `terraform destroy`** gracias a `force_delete` |
| Imagen del juego (Fase 4, **construida y pusheada a mano**) | `sf-tf-workshop-lm:latest` | `sha256:9dd22a3cef18c5c93eb17d79d4a008d748ea32396f96625d1729421f44b8e6e9` | 34.952.071 B (33 MiB comprimido, 112 MB descomprimido) · `linux/amd64` · manifest `v2` simple · base `nginx:alpine` (nginx 1.31.3) · scan on push `COMPLETE` con **0 hallazgos** | Sí, incluido en el costo del repo |
| Rol IAM (Fase 5) | `role-ec2-tf-workshop-lm` | `arn:aws:iam::104981180500:role/role-ec2-tf-workshop-lm` | Trust policy: `sts:AssumeRole` para `Service = ec2.amazonaws.com` · `path = /` · `max_session_duration = 3600` · sin políticas inline · creado `2026-08-18T13:14:48Z` | No. IAM no se cobra |
| Attachment ECR (Fase 5) | — | id compuesto `role-ec2-tf-workshop-lm/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly` | Habilita el `docker pull` del user_data. Incluye `ecr:GetAuthorizationToken`, que es un permiso a nivel cuenta y no de repositorio | No |
| Attachment SSM (Fase 5) | — | id compuesto `role-ec2-tf-workshop-lm/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore` | Habilita Session Manager. Por esto el SG no abre el 22 y no hay key pair en el proyecto | No |
| Instance profile (Fase 5) | `profile-ec2-tf-workshop-lm` | `AIPARQ4K5WBKHX6MIHWCV` (ARN `arn:aws:iam::104981180500:instance-profile/profile-ec2-tf-workshop-lm`) | Envuelve a `role-ec2-tf-workshop-lm`. Es lo único que la API de EC2 sabe consumir: `RunInstances` no acepta un rol | No |
| Instancia EC2 (Fase 6) | `ec2-tf-workshop-lm` | `i-038459aacc0d1e104` | `t3.micro` · AMI `ami-02b3d83d84b07786d` · `us-east-1a` · privada `10.0.1.217` · pública `3.234.229.254` · IMDS `http_tokens = required` · instance profile `profile-ec2-tf-workshop-lm` · lanzada `2026-08-18T13:34:27Z` | **Sí, es lo único que factura de verdad.** `t3.micro` on-demand en `us-east-1`, más el EBS. Se apaga con el `destroy` de la Fase 9 |
| Volumen raíz EBS (Fase 6) | `ebs-root-tf-workshop-lm` | `vol-04d558ac501e8f649` | `gp3` · 8 GiB · `Encrypted: true` con la clave gestionada `aws/ebs` (`b6061ea6-87f4-4eb9-9557-369729891ccb`) | Sí, se cobra por GiB-mes mientras exista. Lo borra el `destroy` junto con la instancia |
| Contenedor del juego (Fase 6, **creado por el user_data, no por Terraform**) | `sf` | `a7f050feb3d3` | Imagen `sf-tf-workshop-lm:latest`, digest `sha256:9dd22a3c…f44b8e6e9` — **idéntico al pusheado en Fase 4** · `-p 80:80` · `--restart unless-stopped` | No por separado: vive dentro de la EC2 |
| Registro DNS tipo A (Fase 7) | `sf.luccamedina.ownboarding.teratest.net` | `Z0909248Q51XTVKXPOG_sf.luccamedina.ownboarding.teratest.net_A` (ID compuesto: zona + nombre + tipo, no un ID de AWS) | `A` → `3.234.229.254` · `ttl = 60` · `allow_overwrite` en su default `false` · **sin tags: los registros de Route53 no son taggables** | Prácticamente no: Route53 cobra por millón de consultas y por hosted zone, y la zona ya existía. Un registro A no-alias suma consultas facturables, a diferencia de un Alias, que no las cobra |

---

## 2. Comandos de verificación y su output

Un bloque por verificación. El output pegado literal, no descrito.

### [Fase 0] — Versión de Terraform vs. requisito del backend

```bash
terraform version
```

```
Terraform v1.15.8
on windows_amd64
```

**Cómo funciona por debajo:** `use_lockfile = true` en el backend S3 usa condicionales de S3
(`If-None-Match`) para el lock, en lugar de un ítem en DynamoDB. Es una capacidad del backend,
así que la restricción es sobre la versión del **CLI**, no del provider AWS. Requiere >= 1.10;
en 1.11+ el argumento `dynamodb_table` quedó deprecado.

**Lectura del output:** 1.15.8 cumple de sobra. Coincide además con la última estable publicada
por la API oficial de releases al momento de la verificación (`api.releases.hashicorp.com` →
`"version":"1.15.8"`), así que no hay upgrade pendiente.

---

### [Fase 0] — Identidad efectiva contra AWS

```bash
aws sts get-caller-identity
```

```json
{
    "UserId": "AIDARQ4K5WBKCAAPWJHQF",
    "Account": "104981180500",
    "Arn": "arn:aws:iam::104981180500:user/luccamedina+tera@gmail.com"
}
```

**Cómo funciona por debajo:** `sts:GetCallerIdentity` no requiere ningún permiso — no se puede
denegar por política. Devuelve la identidad que el SDK resolvió siguiendo la cadena de
credenciales, así que sirve para confirmar **cuál** de todos los perfiles/variables terminó
ganando, no solo que haya credenciales válidas.

**Lectura del output:** cuenta `104981180500`, la misma de `DISENO.md`. Es un usuario IAM
(`AIDA...` como prefijo de UserId = user; un rol asumido daría `AROA...` y un ARN
`assumed-role/...`), consistente con el enunciado que pide access keys estáticas.

---

### [Fase 0] — Permisos IAM reales (adelanto del riesgo de Fase 5)

```bash
aws iam list-attached-user-policies --user-name 'luccamedina+tera@gmail.com'
aws iam get-user --user-name 'luccamedina+tera@gmail.com' --query 'User.PermissionsBoundary'
aws organizations describe-organization
aws iam simulate-principal-policy \
  --policy-source-arn 'arn:aws:iam::104981180500:user/luccamedina+tera@gmail.com' \
  --action-names iam:CreateRole iam:CreateInstanceProfile iam:AttachRolePolicy iam:PassRole \
                 iam:AddRoleToInstanceProfile ec2:CreateVpc ec2:RunInstances \
                 ecr:CreateRepository s3:CreateBucket s3:PutObject \
                 route53:ChangeResourceRecordSets \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output table
```

```
{
    "AttachedPolicies": [
        { "PolicyName": "AdministratorAccess",   "PolicyArn": "arn:aws:iam::aws:policy/AdministratorAccess" },
        { "PolicyName": "IAMUserChangePassword", "PolicyArn": "arn:aws:iam::aws:policy/IAMUserChangePassword" }
    ]
}

null

An error occurred (AWSOrganizationsNotInUseException) when calling the
DescribeOrganization operation: Your account is not a member of an organization.

-------------------------------------------------
|            SimulatePrincipalPolicy            |
+------------------------------------+----------+
|  iam:CreateRole                    |  allowed |
|  iam:CreateInstanceProfile         |  allowed |
|  iam:AttachRolePolicy              |  allowed |
|  iam:PassRole                      |  allowed |
|  iam:AddRoleToInstanceProfile      |  allowed |
|  ec2:CreateVpc                     |  allowed |
|  ec2:RunInstances                  |  allowed |
|  ecr:CreateRepository              |  allowed |
|  s3:CreateBucket                   |  allowed |
|  s3:PutObject                      |  allowed |
|  route53:ChangeResourceRecordSets  |  allowed |
+------------------------------------+----------+
```

**Cómo funciona por debajo:** el permiso efectivo de una acción no sale de una sola política.
La evaluación de IAM aplica, en orden, un `Deny` explícito de cualquier capa (gana siempre),
después SCPs de la organización, permissions boundary, y recién ahí las políticas de identidad.
`AdministratorAccess` solo cubre la última capa. Por eso hay que mirar las otras dos por
separado: `PermissionsBoundary: null` (no hay techo) y `AWSOrganizationsNotInUseException`
(la cuenta es standalone, no hay SCPs posibles).

**Limitación conocida de la herramienta:** `simulate-principal-policy` **no** evalúa SCPs. Si la
cuenta hubiera estado en una organización, la tabla de `allowed` habría sido engañosa. Ese es
justamente el escenario clásico en que Fase 5 explota con `AccessDenied` sin que las políticas
del usuario expliquen nada.

**Lectura del output:** las tres capas dan verde. El riesgo "Permisos IAM del usuario" de
`DISENO.md` §6 queda **cerrado**, verificado antes de Fase 5 y no durante.

---

### [Fase 0] — Bucket de estado creado y endurecido (fuera de Terraform)

```bash
BUCKET=tf-state-workshop-lm-104981180500

aws s3api create-bucket --bucket "$BUCKET" --region us-east-1
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# verificacion
aws s3api get-bucket-versioning     --bucket "$BUCKET"
aws s3api get-bucket-encryption     --bucket "$BUCKET"
aws s3api get-public-access-block   --bucket "$BUCKET"
aws s3api get-bucket-location       --bucket "$BUCKET"
aws s3api list-objects-v2 --bucket "$BUCKET" --query 'KeyCount'
```

```json
{
    "Location": "/tf-state-workshop-lm-104981180500",
    "BucketArn": "arn:aws:s3:::tf-state-workshop-lm-104981180500"
}

{ "Status": "Enabled" }

{
    "ServerSideEncryptionConfiguration": {
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" },
                "BucketKeyEnabled": true,
                "BlockedEncryptionTypes": { "EncryptionType": ["SSE-C"] }
            }
        ]
    }
}

{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
}

{ "LocationConstraint": null }

null
```

**Cómo funciona por debajo:** las tres protecciones son subrecursos independientes del bucket,
no argumentos del `create-bucket` — de ahí que sean cuatro llamadas separadas a la API y no una.
El **versioning** es lo que convierte al bucket en una red de seguridad real para el estado: cada
`apply` sobrescribe la misma key (`terraform.tfstate`), así que sin versiones un estado corrupto
sería irrecuperable; con versiones, cada `apply` deja atrás la versión anterior restaurable.
El **block public access** es la capa que gana por encima de cualquier ACL o bucket policy futura,
incluso una mal escrita.

**Lectura del output — dos cosas contraintuitivas:**

1. `"LocationConstraint": null` **no** es un error ni un bucket sin región. `us-east-1` es la
   región original de S3 y funciona como valor por defecto del protocolo: es la única que se
   representa como ausencia de constraint. Por eso además el `create-bucket` de `us-east-1` es
   el único que **no** lleva `--create-bucket-configuration LocationConstraint=...` — pasarlo
   ahí falla con `InvalidLocationConstraint`. El bucket está correctamente en `us-east-1`.
2. `"BlockedEncryptionTypes": {"EncryptionType": ["SSE-C"]}` aparece sin que se haya pedido: es
   un default nuevo de S3 que devuelve la API, no algo que haya configurado el comando.

`KeyCount` → `null` confirma que el bucket está vacío, como corresponde: el objeto de estado
recién va a aparecer en la Fase 3, cuando se migre el backend.

---

### [Fase 0] — Cierre: `init` + `validate` + `plan` sobre la config base

Config de partida: `versions.tf` (required_version + required_providers + backend local),
`providers.tf` (provider aws con default_tags), `variables.tf` (region + default_tags).
Todavía sin ningún `resource`.

```bash
terraform fmt
terraform init
terraform validate
terraform plan
```

```
- Reusing previous version of hashicorp/aws from the dependency lock file
- Using previously-installed hashicorp/aws v6.60.0

Terraform has been successfully initialized!

Success! The configuration is valid.

No changes. Your infrastructure matches the configuration.
Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

**Cómo funciona por debajo:** los tres comandos verifican cosas distintas y por eso hay que
correr los tres. `init` resuelve y descarga providers y prepara el backend, pero **no** valida
referencias entre bloques — de hecho pasó en verde una config que referenciaba `var.region`
antes de que existiera `variables.tf`. `validate` sí chequea la coherencia interna del módulo
(tipos, referencias, argumentos válidos) pero sin hablar con AWS. `plan` es el único que además
consulta la API real y compara contra el estado.

**Lectura del output:** `No changes` con cero recursos declarados es exactamente el resultado
esperado y es un resultado **positivo**: significa que las credenciales resolvieron, que el
provider se conectó a AWS y que el estado (vacío) coincide con la config (vacía). Confirma toda
la cadena de plomería antes de agregar el primer recurso.

**Verificación de que el backend quedó registrado:**

```bash
cat .terraform/terraform.tfstate
```

```json
{
  "version": 3,
  "terraform_version": "1.15.8",
  "backend": {
    "type": "local",
    "config": { "path": "terraform.tfstate", "workspace_dir": null },
    "hash": 73024536
  }
}
```

Este archivo **no es** el estado de la infraestructura — es donde Terraform anota qué backend
tiene configurado. Antes de declarar `backend "local" {}` no existía, porque con el backend
implícito no hay configuración que registrar. El `hash` es la pieza clave de la Fase 3: cuando
el bloque pase a `"s3"` el hash deja de coincidir, Terraform detecta el cambio de backend y
ofrece migrar el estado.

`CAPTURA PENDIENTE -- consola de S3, bucket tf-state-workshop-lm-104981180500, pestaña
Properties: se tienen que ver Bucket Versioning = Enabled y Default encryption = SSE-S3 (AES256)`

---

### [Fase 1] — `apply` de data sources: cero recursos creados

```bash
terraform apply
```

```
data.aws_route53_zone.main: Reading...
data.aws_ami.al2023: Reading...
data.aws_ami.al2023: Read complete after 2s [id=ami-07a5b367e8dc8bd92]
data.aws_route53_zone.main: Read complete after 2s [id=Z0909248Q51XTVKXPOG]

Changes to Outputs:
  + al2023_ami_id          = "ami-07a5b367e8dc8bd92"
  + al2023_ami_name        = "al2023-ami-2023.12.20260803.3-kernel-6.1-x86_64"
  + main_route53_zone_arn  = "arn:aws:route53:::hostedzone/Z0909248Q51XTVKXPOG"
  + main_route53_zone_id   = "Z0909248Q51XTVKXPOG"
  + main_route53_zone_name = "luccamedina.ownboarding.teratest.net"

Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

**Cómo funciona por debajo:** los data sources se resuelven **en paralelo** — se ve en los dos
`Reading...` consecutivos antes de cualquier `Read complete`. Terraform no tiene motivo para
serializarlos porque no hay ninguna referencia entre ellos, y eso ya es el grafo de dependencias
trabajando: sin aristas, todo va en paralelo.

**Lectura del output:** `Resources: 0 added, 0 changed, 0 destroyed` con cinco outputs impresos
**es** el criterio de salida de la fase. Confirma en la práctica que un data source lee y no
crea: ni la hosted zone ni la AMI existen por causa de este código. La sección se llama
`Changes to Outputs` y no `Terraform will perform the following actions` precisamente porque no
hay acciones sobre infraestructura.

---

### [Fase 1] — Anatomía del `terraform.tfstate` recién nacido

```bash
ls -l terraform.tfstate
git check-ignore -v terraform.tfstate
```

```
-rw-r--r-- 1 lucca lucca 5065 terraform.tfstate
.gitignore:7:*.tfstate	terraform.tfstate
```

Cabecera y contenido:

```
  version: 4
  terraform_version: 1.15.8
  serial: 1
  lineage: 28d49728-1e43-f4d8-8f9d-ef9fa384e9eb
  recursos en el estado: 2
  outputs en el estado: 5

  mode=data     type=aws_ami              name=al2023   atributos=44
  mode=data     type=aws_route53_zone     name=main     atributos=15
```

**Cómo funciona por debajo — cuatro cosas que se leen acá y en ningún otro lado:**

1. **`mode: data`**, no `managed`. Es la distinción estructural entre leer y crear, y está
   escrita en el estado. Los recursos que Terraform administra y puede destruir van a aparecer
   como `managed` a partir de la Fase 2. Un `terraform destroy` no toca las entradas `data`.
2. **44 atributos guardados para la AMI**, contra los 2 que se expusieron como output. Terraform
   guarda **todo** lo que leyó, no solo lo que se usa. Ahí está la razón por la que el estado es
   sensible: no controlás qué queda adentro.
3. **`serial: 1`** — se incrementa en cada escritura del estado. Es el número que permite
   detectar escrituras concurrentes.
4. **`lineage`** — un UUID que identifica *este* estado como linaje. Sobrevive a la migración de
   backend de la Fase 3: si después del `init -migrate-state` el lineage cambiara, significaría
   que se creó un estado nuevo en vez de haberse movido el existente.

**Verificación de seguridad:** `git check-ignore` confirma que la regla `*.tfstate` de la línea
7 del `.gitignore` lo está tomando. El archivo con 44 atributos de infraestructura leída no entra
al repo.

**Datos útiles que quedaron en el estado para fases siguientes:**

| Atributo | Valor | Dónde importa |
|---|---|---|
| `imds_support` | `v2.0` | Fase 6: la AMI exige IMDSv2, hay que tenerlo en cuenta si el `user_data` consulta metadata |
| `root_device_name` | `/dev/xvda` | Fase 6, si se toca el `root_block_device` |
| `virtualization_type` / `ena_support` | `hvm` / `true` | Compatible con `t3.micro` |
| `deprecation_time` | `2026-11-01T17:47:00Z` | La AMI se deprecia en ~3 meses; irrelevante para este lab pero es el tipo de cosa que rompe un pipeline meses después |
| `image_owner_alias` | `amazon` | Confirma que es oficial y no de un tercero que se llamó igual |

---

### [Fase 2] — `plan` de la red completa: 10 recursos, ninguno aplicado todavía

Config agregada en esta fase: `locals.tf` (nombre derivado), `network.tf` (VPC, 2 subnets, IGW,
route table, association, SG + 3 reglas), 4 variables nuevas y 4 outputs nuevos.

```bash
terraform fmt && terraform validate && terraform plan
```

```
Success! The configuration is valid.

Plan: 10 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + al2023_ami_id              = "ami-07a5b367e8dc8bd92"
  + al2023_ami_name            = "al2023-ami-2023.12.20260803.3-kernel-6.1-x86_64"
  + instance_security_group_id = (known after apply)
  + main_route53_zone_arn      = "arn:aws:route53:::hostedzone/Z0909248Q51XTVKXPOG"
  + main_route53_zone_id       = "Z0909248Q51XTVKXPOG"
  + main_route53_zone_name     = "luccamedina.ownboarding.teratest.net"
  + private_subnet_id          = (known after apply)
  + public_subnet_id           = (known after apply)
  + vpc_id                     = (known after apply)
```

Extracto de un recurso, para ver los dos campos que importan:

```
  # aws_subnet.public will be created
  + resource "aws_subnet" "public" {
      + availability_zone       = "us-east-1a"
      + cidr_block              = "10.0.1.0/24"
      + map_public_ip_on_launch = true
      + vpc_id                  = (known after apply)
      + tags                    = {
          + "Name" = "subnet-public-tf-workshop-lm"
        }
      + tags_all                = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "subnet-public-tf-workshop-lm"
          + "Repository"  = "terraform-practice-teracloud"
        }
    }
```

**Cómo funciona por debajo — dos lecturas:**

1. **`(known after apply)` es el grafo de dependencias hecho visible.** Casi todos los `vpc_id`
   aparecen así porque el ID todavía no existe: AWS lo asigna al crear la VPC. Ese "no lo sé aún"
   es justamente lo que **obliga** al orden de creación — Terraform no puede crear la subnet antes
   de tener con qué llenar el campo. Por eso no hace falta ningún `depends_on`: el orden del
   `DISENO.md` §4 se cumple solo, derivado de las referencias.
2. **`tags` vs `tags_all`**: `tags` es lo que se declaró en el recurso; `tags_all` es el resultado
   final con los `default_tags` del provider ya mezclados. Los cuatro tags aparecen en los 10
   recursos sin haberlos escrito 10 veces. Si un recurso declarara `Environment`, el suyo pisaría
   al del provider.

**Estado al cierre de la sesión**: el `apply` **no se corrió**. Verificado contra AWS que la cuenta
sigue limpia:

```bash
aws ec2 describe-vpcs --region us-east-1 --query 'Vpcs[].{id:VpcId,cidr:CidrBlock,default:IsDefault}'
```

```json
[
    {
        "id": "vpc-08bacc1ca6a59f5dc",
        "cidr": "172.31.0.0/16",
        "default": true
    }
]
```

Solo la VPC default de la cuenta. Ningún recurso del workshop existe todavía.

`CAPTURA PENDIENTE -- consola de VPC, us-east-1, vista Your VPCs filtrada por tag Name =
vpc-tf-workshop-lm: se tiene que ver la VPC 10.0.0.0/16 con sus 4 tags; y en Subnets, las dos
subnets con su AZ distinta (us-east-1a / us-east-1b)`

---

### [Fase 2] — `apply` de la red: 10 recursos creados y verificados contra la API

El `apply` lo corrió Lucca en una terminal real, desde WSL (pide el `yes` por TTY; ver
troubleshooting §3, primer bloque). **La salida literal del `apply` no quedó capturada** — lo que
sigue es la verificación posterior, corrida contra el estado y contra la API de AWS, que es la que
tiene valor probatorio de todas formas: el `apply` dice lo que Terraform *cree* que hizo, y esto
dice lo que AWS *tiene*.

```bash
terraform output -json
```

```json
{
  "al2023_ami_id":              { "value": "ami-02b3d83d84b07786d" },
  "al2023_ami_name":            { "value": "al2023-ami-2023.12.20260817.0-kernel-6.1-x86_64" },
  "instance_security_group_id": { "value": "sg-0b1c39e081bc25b04" },
  "main_route53_zone_arn":      { "value": "arn:aws:route53:::hostedzone/Z0909248Q51XTVKXPOG" },
  "main_route53_zone_id":       { "value": "Z0909248Q51XTVKXPOG" },
  "main_route53_zone_name":     { "value": "luccamedina.ownboarding.teratest.net" },
  "private_subnet_id":          { "value": "subnet-03eb6819b955061da" },
  "public_subnet_id":           { "value": "subnet-0033c17b9c7ec238c" },
  "vpc_id":                     { "value": "vpc-09b6544aea696e9dd" }
}
```

**Lo primero que salta no es un recurso de red: cambió la AMI.**

| | Fase 1 (14-ago-2026) | Fase 2 (18-ago-2026) |
|---|---|---|
| `al2023_ami_id` | `ami-07a5b367e8dc8bd92` | `ami-02b3d83d84b07786d` |
| `al2023_ami_name` | `al2023-ami-2023.12.20260803.3-kernel-6.1-x86_64` | `al2023-ami-2023.12.20260817.0-kernel-6.1-x86_64` |

Cuatro días, cero líneas de código tocadas, ID distinto. Es exactamente el segundo efecto de
`most_recent = true` anticipado en §6 —"un `plan` corrido semanas después puede proponer destruir y
recrear la instancia sin que haya cambiado una línea de código"— y ocurrió antes de lo previsto y
solo. Hoy es inocuo porque `aws_instance` todavía no existe; **a partir de la Fase 6 este mismo
cambio deja de ser una línea en `Changes to Outputs` y pasa a ser un `# forces replacement` sobre la
EC2**, porque el argumento `ami` no se puede modificar en caliente. Anotado como el dato a mirar
primero si un `plan` de la Fase 8 propone reemplazos que nadie pidió.

Verificación contra la API (no contra el estado):

```bash
VPC=$(terraform output -raw vpc_id)
SG=$(terraform output -raw instance_security_group_id)

aws ec2 describe-vpc-attribute --vpc-id "$VPC" --attribute enableDnsHostnames --query 'EnableDnsHostnames.Value'
aws ec2 describe-vpc-attribute --vpc-id "$VPC" --attribute enableDnsSupport   --query 'EnableDnsSupport.Value'
aws ec2 describe-subnets            --filters "Name=vpc-id,Values=$VPC" --output table
aws ec2 describe-internet-gateways  --filters "Name=attachment.vpc-id,Values=$VPC" --output table
aws ec2 describe-route-tables       --filters "Name=vpc-id,Values=$VPC" --output json
aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG" --output table
```

```
=== DNS attrs ===
true
true

=== SUBNETS ===
+------------+--------------+----------------------------+---------------------------------+--------+
|     az     |    cidr      |            id              |              name               | pubIP  |
+------------+--------------+----------------------------+---------------------------------+--------+
|  us-east-1a|  10.0.1.0/24 |  subnet-0033c17b9c7ec238c  |  subnet-public-tf-workshop-lm   |  True  |
|  us-east-1b|  10.0.2.0/24 |  subnet-03eb6819b955061da  |  subnet-private-tf-workshop-lm  |  False |
+------------+--------------+----------------------------+---------------------------------+--------+

=== IGW ===
+------------------------+-------------+
|           id           |    state    |
+------------------------+-------------+
|  igw-03d79e19ed587867e |  available  |
+------------------------+-------------+

=== ROUTE TABLES ===
+------+----------------------------+-------------------------+----------------------------+
| main |           name             |           rt            |          subnet            |
+------+----------------------------+-------------------------+----------------------------+
|False |  rt-public-tf-workshop-lm  |  rtb-0e538ac0b28dbd036  |  subnet-0033c17b9c7ec238c  |
|  True|  None                      |  rtb-0e10176026f1fca6c  |  None                      |
+------+----------------------------+-------------------------+----------------------------+

[
    {
        "rt": "rtb-0e538ac0b28dbd036",
        "routes": [
            { "dest": "10.0.0.0/16", "gw": "local",                  "state": "active" },
            { "dest": "0.0.0.0/0",   "gw": "igw-03d79e19ed587867e",  "state": "active" }
        ]
    },
    {
        "rt": "rtb-0e10176026f1fca6c",
        "routes": [
            { "dest": "10.0.0.0/16", "gw": "local",                  "state": "active" }
        ]
    }
]

=== SG RULES ===
+-----------+--------------------------------------------------------------------+---------+-------+------------------------+--------+--------+
|   cidr    |                               desc                                 | egress  | from  |          id            | proto  |  to    |
+-----------+--------------------------------------------------------------------+---------+-------+------------------------+--------+--------+
|  0.0.0.0/0|  HTTP publico hacia el juego                                       |  False  |  80   |  sgr-00b6e69b2098978b4 |  tcp   |  80    |
|  0.0.0.0/0|  Puerto de la aplicacion, abierto solo para debug del lab          |  False  |  8080 |  sgr-047ba8d2ffd001523 |  tcp   |  8080  |
|  0.0.0.0/0|  Salida total: docker pull desde ECR y yum update en el user_data  |  True   |  -1   |  sgr-06ba0b4abc932a07f |  -1    |  -1    |
+-----------+--------------------------------------------------------------------+---------+-------+------------------------+--------+--------+
```

**Las tres cosas que esta salida confirma y que no se pueden ver en el `plan`:**

1. **La main route table existe, tiene ID propio (`rtb-0e10176026f1fca6c`) y Terraform no la
   administra.** Aparece con `main: True`, sin tag `Name` y sin subnet asociada, con la única ruta
   `local`. Es la prueba de campo de lo escrito en §6: la subnet privada no tiene ningún recurso
   que la haga privada — cae acá por descarte y acá no hay `0.0.0.0/0`. En el `terraform state list`
   no figura, porque no es suya. **Ojo en la Fase 8**: esta tabla es un recurso real de la VPC que
   el código no conoce, o sea el candidato natural para el ejercicio de `import`.
2. **La ruta `10.0.0.0/16 → local` está en las dos tablas** y nunca se escribió en el HCL. AWS la
   pone sola y no se puede borrar. Confirmado que **no es drift** antes de llegar a la Fase 8, que
   es cuando se va a comparar el `plan` contra la consola.
3. **Las reglas de SG son objetos con ID propio `sgr-...`**, listables por una API dedicada
   (`describe-security-group-rules`, que no existía en la era de las reglas inline). Cada una tiene
   su `Description` propia, cosa que un bloque `ingress {}` inline no permite por regla. Es lo que
   hace que los diffs sean quirúrgicos.

Estado después del `apply`:

```bash
terraform state list
```

```
data.aws_ami.al2023
data.aws_route53_zone.main
aws_internet_gateway.main
aws_route_table.public
aws_route_table_association.public
aws_security_group.instance
aws_subnet.private
aws_subnet.public
aws_vpc.main
aws_vpc_security_group_egress_rule.all
aws_vpc_security_group_ingress_rule.app
aws_vpc_security_group_ingress_rule.http
```

```
serial   11
lineage  bb05f068-952b-8a96-bc69-731f58f919cb
managed  10
data     2
```

**Dos lecturas del estado, las dos importantes para la Fase 3:**

- **`serial: 11`, no `1`.** El serial no cuenta `apply`s, cuenta **escrituras del archivo de
  estado**: Terraform lo persiste a medida que cada recurso termina, no una vez al final. Por eso
  un `apply` de 10 recursos deja el serial en dos dígitos. Es también la razón por la que un
  `apply` interrumpido a la mitad no pierde lo ya creado.
- **`lineage: bb05f068-952b-8a96-bc69-731f58f919cb`**, distinto del `28d49728-...` que tenía el
  estado de la Fase 1. No es un problema: aquel `terraform.tfstate` se había borrado entre sesiones
  y sin recursos managed que perder, así que el `apply` de hoy arrancó un linaje nuevo.

  > **Corrección posterior (Fase 3).** Acá se anotó que este UUID era el invariante a verificar
  > después del `init -migrate-state`, y que un lineage distinto significaría estado nuevo y
  > recursos huérfanos. **Es falso**, y se comprobó en vivo al migrar: el lineage cambió y no se
  > perdió nada. El desarrollo completo está en el bloque de Fase 3 de esta misma sección.

`CAPTURA PENDIENTE -- consola de VPC, us-east-1, Route Tables filtrado por VPC vpc-09b6544aea696e9dd:
se tienen que ver las DOS tablas, la rt-public-tf-workshop-lm con la ruta 0.0.0.0/0 al IGW y su
subnet asociada, y la main sin nombre con solo la ruta local y "Main: Yes"`

`CAPTURA PENDIENTE -- consola de EC2, Security Groups, sg-0b1c39e081bc25b04, pestaña Inbound rules:
se tienen que ver las dos reglas con su Description propia y su Rule ID sgr-...`

---

### [Fase 3] — Migración del backend local a S3

Diff de la fase: **un solo bloque** de `versions.tf`. Nada más.

```hcl
# antes
backend "local" {
  path = "terraform.tfstate"
}

# despues
backend "s3" {
  bucket       = "tf-state-workshop-lm-104981180500"
  key          = "tf-workshop/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true
}
```

```bash
terraform fmt && terraform validate   # fmt: sin salida. validate: Success!
terraform init -migrate-state         # corrido en terminal real: pide "yes" por TTY
```

```
Initializing the backend...
Terraform detected that the backend type changed from "local" to "s3".
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "s3" backend. No existing state was found in the newly
  configured "s3" backend. Do you want to copy this state to the new "s3"
  backend? Enter "yes" to copy and "no" to start with an empty state.

  Enter a value: yes

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
- Reusing previous version of hashicorp/aws from the dependency lock file
- Using previously-installed hashicorp/aws v6.60.0

Terraform has been successfully initialized!
```

**Detalle que confirma algo de la Fase 0:** el `init` detectó el cambio de backend porque el `hash`
guardado en `.terraform/terraform.tfstate` dejó de coincidir. Pasó de `73024536` (local) a
`2869535846` (s3). Ese archivo, que en la Fase 0 parecía un dato de color, es exactamente el
mecanismo que dispara la pregunta de migración.

**`validate` no valida el backend.** Dio `Success!` con el bloque `s3` recién escrito y sin haber
tocado AWS: no chequea que el bucket exista, ni que haya permisos, ni que la key sea alcanzable.
El único comando que prueba el backend de verdad es `init`.

#### Verificación del criterio de salida

```bash
B=tf-state-workshop-lm-104981180500
K=tf-workshop/terraform.tfstate

aws s3api list-object-versions --bucket "$B" --output json     # con Key en la proyeccion
aws s3api head-object --bucket "$B" --key "$K" --query '{enc:ServerSideEncryption,size:ContentLength}'
aws s3api get-object  --bucket "$B" --key "$K" /tmp/s3state.json   # leer el estado DEL BUCKET
terraform plan
```

```json
{ "enc": "AES256", "size": 22958, "vid": "tz0UMyt0NcjgjjCejyuFF_lRciRR9K0x" }
```

```
# estado bajado del bucket, no del disco
lineage 8976e38b-cd80-4322-ef04-a4c95169a08f
serial  1
managed 10
data    2
```

```
aws_vpc.main: Refreshing state... [id=vpc-09b6544aea696e9dd]
aws_subnet.public: Refreshing state... [id=subnet-0033c17b9c7ec238c]
aws_security_group.instance: Refreshing state... [id=sg-0b1c39e081bc25b04]
aws_route_table_association.public: Refreshing state... [id=rtbassoc-04d172e50037a766b]
...
No changes. Your infrastructure matches the configuration.
Releasing state lock. This may take a few moments...
```

| Chequeo | Resultado |
|---|---|
| Objeto presente en S3 | `tf-workshop/terraform.tfstate`, 22.958 bytes |
| Cifrado en reposo | `ServerSideEncryption: AES256` — el `encrypt = true` llegó al `PutObject` |
| Versioning activo | Registró la escritura con `VersionId` propio |
| Backend registrado | `.terraform/terraform.tfstate` → `type: s3`, `hash: 2869535846` |
| Respaldo local | `terraform.tfstate` sigue en disco (`bb05f068`, serial 11, 12 recursos) e ignorado por `.gitignore:7` |
| Recursos preservados | 10 managed + 2 data, todos refrescan por su ID real |
| `plan` | `No changes` |

#### El error que cometí en la predicción, y por qué importa

**Lo que estaba anotado antes de migrar:** "si tras migrar el lineage no es `bb05f068-...`, no se
migró el estado, se creó uno nuevo y los 10 recursos quedaron huérfanos".

**Lo que pasó:** el lineage cambió (`bb05f068-...` → `8976e38b-...`), el serial se reseteó de 11 a
1, y **no se perdió absolutamente nada** — los 10 recursos están en el objeto de S3 y el `plan` da
`No changes`.

**Causa, verificada contra la fuente y no contra la intuición** — `internal/states/remote/state.go`
del repo de HashiCorp, método `PersistState`:

```go
if s.lineage == "" { // indicates that no state snapshot is present yet
    lineage, err := uuid.GenerateUUID()
    if err != nil {
        return fmt.Errorf("failed to generate initial lineage: %v", err)
    }
    s.lineage = lineage
    s.serial++
```

El backend S3 estaba vacío, así que el gestor de estado remoto **acuña un lineage nuevo y arranca
el serial en 1**. Migrar hacia un destino vacío siempre hace esto. No es un síntoma de nada.

**La lección, que es la que vale**: el lineage identifica la continuidad de un estado **dentro de
un mismo backend** — es lo que detecta que alguien reemplazó tu archivo de estado por otro
distinto entre dos escrituras al mismo lugar. A través de una migración a un destino vacío no
tiene sentido compararlo. El invariante correcto para juzgar una migración es otro, y son tres
cosas: **el conjunto de recursos, sus IDs reales, y un `plan` que diga `No changes`**. Eso es lo
que prueba que el estado sigue apuntando a la misma infraestructura.

Generalizable: un invariante elegido por intuición puede ser a la vez plausible y equivocado. Antes
de usar un campo como criterio de aceptación, hay que saber **quién lo escribe y cuándo**.

#### El lock, que se puede ver y leer

Listando versiones **con la Key en la proyección** aparecen dos objetos distintos, no uno:

```
tf-workshop/terraform.tfstate           22958  12:25:27   (1 version, el estado)
tf-workshop/terraform.tfstate.tflock      254  12:25:12   (el init)
tf-workshop/terraform.tfstate.tflock      244  12:26:15   (el plan)

DeleteMarkers:
tf-workshop/terraform.tfstate.tflock           12:25:27   (unlock del init)
tf-workshop/terraform.tfstate.tflock           12:26:25   (unlock del plan)
```

Dos ciclos lock/unlock completos con su delete marker cada uno. Y el contenido del lock es legible:

```json
{"ID":"ea1f3de2-be0e-273c-e2a1-0ab301156572","Operation":"OperationTypePlan","Info":"",
 "Who":"lucca@LUQUITA","Version":"1.15.8","Created":"2026-08-18T12:26:13.211078748Z",
 "Path":"tf-state-workshop-lm-104981180500/tf-workshop/terraform.tfstate"}
```

Ahí está, en concreto, por qué `use_lockfile` no necesita DynamoDB: **el lock es un objeto de S3**,
creado con escrituras condicionales y borrado al terminar. El campo `Who` es literalmente lo que
aparecería en el `Error acquiring the state lock` de un segundo `apply` simultáneo, y `Operation`
distingue si el que tiene el lock está planificando o aplicando.

**Trampa de lectura anotada**: `--prefix tf-workshop/terraform.tfstate` matchea **también** el
`.tflock`, porque es prefijo, no nombre exacto. En la primera lectura interpreté los objetos de 254
y 244 bytes como versiones viejas del estado. Si se listan versiones de un estado, hay que proyectar
`Key` — si no, se están mirando dos objetos distintos creyendo que son uno.

`CAPTURA PENDIENTE -- consola de S3, bucket tf-state-workshop-lm-104981180500, objeto
tf-workshop/terraform.tfstate con "Show versions" activado: se tiene que ver la version del estado
y, si se captura durante un apply, el objeto hermano terraform.tfstate.tflock`

---

### [Fase 4] — ECR creado por Terraform, imagen construida y pusheada a mano

Config agregada: `ecr.tf` (un recurso), la variable `game_name` y el output `ecr_repository_url`.

```bash
terraform fmt && terraform validate && terraform apply
```

```
  # aws_ecr_repository.game will be created
  + resource "aws_ecr_repository" "game" {
      + force_delete         = true
      + image_tag_mutability = "MUTABLE"
      + name                 = "sf-tf-workshop-lm"
      + repository_url       = (known after apply)
      + image_scanning_configuration {
          + scan_on_push = true
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.

aws_ecr_repository.game: Creating...
aws_ecr_repository.game: Creation complete after 1s [id=sf-tf-workshop-lm]
Releasing state lock. This may take a few moments...

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

ecr_repository_url = "104981180500.dkr.ecr.us-east-1.amazonaws.com/sf-tf-workshop-lm"
```

**Detalle del `id`**: es `sf-tf-workshop-lm`, el nombre — no un ARN ni un identificador opaco.
ECR usa el nombre como identidad, que es la razón por la que ese nombre tiene reglas de formato
(solo minúsculas, `[a-z0-9._/-]`) y por la que cambiarlo fuerza reemplazo. Tercera aparición de la
distinción `name` (identificador con reglas del servicio) vs. tag `Name` (texto libre): ya había
mordido en el SG de la Fase 2.

#### Elección de la imagen: verificada abriendo las capas, no leyendo descripciones

Ninguno de los candidatos de Docker Hub tenía descripción útil. Se resolvió bajando el manifest y
destarando las capas de cada uno:

| Candidata | Veredicto |
|---|---|
| `tertiaryinfotech/street-fighter-game` | **Solo arm64** — no bootea en `t3.micro` |
| `rmelamud/street-fighter` | 418 MB de Node, `npm start` en 8080 |
| `alinablankselina/street-fighter` | 398 MB de Node, sin `ExposedPorts` declarado |
| `appachey/street-fighter` | `php -S 0.0.0.0:8082`, 132 MB |
| `simeontchakarov/streetfighter2` | ASP.NET 10 en 8080, 121 MB |
| `mattrayner/doom` | **No existe** — `object not found` |
| `darmos/streetfighter` | nginx en **80**, 54 MiB, amd64. La única servible tal cual |

Contenido real de `darmos/streetfighter`, leído de la capa de aplicación:

```
usr/share/nginx/html/index.html
usr/share/nginx/html/js/{ken.js, audio.js, jquery.min.js, soundmanager2-jsmin.js}
usr/share/nginx/html/css/style.css
usr/share/nginx/html/images/{ken.png, guile.png, ken-shoryuken.png, ...}
usr/share/nginx/html/audio/{hado.wav, shoryu.wav, tatsumaki-senpuu-kyaku.wav, music.mp3}
```

Es el demo **Street Fighter II en CSS puro** de `jkneb` (tutorial del blog de David Walsh). Estático
y autocontenido: jQuery viene adentro, no hay CDN externo, así que arranca sin salida a internet.
Su base es Debian stretch + nginx 1.13, **las dos EOL**, y se iba a exponer en `0.0.0.0/0:80` — de
ahí la decisión de construirla nosotros desde el fuente original (`jkneb/street-fighter-css`, 48
stars) sobre `nginx:alpine`.

#### Build local y smoke test antes de pushear

```dockerfile
FROM nginx:alpine
COPY . /usr/share/nginx/html
```

```
.dockerignore
-------------
.git
.gitignore
Dockerfile
.dockerignore
scss
readme.md
```

```bash
docker build --provenance=false -t sf:local /tmp/sf
docker run -d --rm -p 8080:80 --name sftest sf:local
curl -sI http://localhost:8080/
for p in index.html css/style.css js/ken.js images/ken.png audio/music.mp3 .git/config; do
  curl -s -o /dev/null -w "$p %{http_code} %{size_download}B\n" http://localhost:8080/$p
done
```

```
HTTP/1.1 200 OK
Server: nginx/1.31.3

index.html      200 1389B
css/style.css   200 15003B
js/ken.js       200 8377B
images/ken.png  200 120943B
audio/music.mp3 200 2288977B
.git/config     404          <-- el .dockerignore hizo su trabajo
```

**Por qué el `.dockerignore` no es cosmético.** El primer `Dockerfile` era
`COPY . /usr/share/nginx/html` sobre un directorio recién clonado, o sea que **nginx habría servido
el `.git/` por HTTP**: 12,5 MB de packfiles desde los que se reconstruye el repositorio y su
historial completo. Acá el fuente es público y no cambia nada, pero es el patrón exacto con el que
se filtran credenciales en `.git/config` o en commits viejos. El `404` de arriba es la verificación
de que quedó afuera. Y no alcanza con sacarlo del `COPY`: `.dockerignore` actúa **antes**, al armar
el contexto, así que los archivos ni siquiera llegan al daemon.

#### Login y push

```bash
REG=104981180500.dkr.ecr.us-east-1.amazonaws.com
ECR=$REG/sf-tf-workshop-lm

aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$REG"
docker build --provenance=false -t "$ECR:latest" /tmp/sf
docker push "$ECR:latest"
```

```
Login Succeeded

1223f016b4e4: Pushed
46f977ee452f: Pushed
390dc935348d: Pushed
d0008c891db4: Pushed
62bec68d7c31: Pushed
3cd534fe98c6: Pushed
55afa1ecc21d: Pushed
a06fd7c7adf7: Pushed
46519e7231d2: Pushed
latest: digest: sha256:9dd22a3cef18c5c93eb17d79d4a008d748ea32396f96625d1729421f44b8e6e9 size: 2071
```

**Por qué el login se escribe exactamente así.** `get-login-password` devuelve un token temporal
(12 h) y el usuario es siempre literalmente `AWS` — no es el nombre del usuario IAM. La parte que
importa es `--password-stdin`: pasarlo como `--password <token>` lo deja en el historial de la
shell y visible en la tabla de procesos para cualquier usuario de la máquina. Con ese token se
escribe en el registry.

#### Criterio de salida de la fase

```bash
aws ecr list-images --repository-name sf-tf-workshop-lm --region us-east-1
aws ecr describe-images --repository-name sf-tf-workshop-lm --region us-east-1
aws ecr describe-image-scan-findings --repository-name sf-tf-workshop-lm --image-id imageTag=latest --region us-east-1
aws ecr describe-repositories --repository-names sf-tf-workshop-lm --region us-east-1
```

```json
{ "imageIds": [ { "imageDigest": "sha256:9dd22a3c...f44b8e6e9", "imageTag": "latest" } ] }

[ { "tags": ["latest"], "mb": 34952071, "pushed": "2026-08-18T12:51:45Z",
    "manifest": "application/vnd.docker.distribution.manifest.v2+json" } ]

{ "status": { "status": "COMPLETE", "description": "The scan was completed successfully." },
  "counts": {} }

[ { "url": "104981180500.dkr.ecr.us-east-1.amazonaws.com/sf-tf-workshop-lm",
    "mutability": "MUTABLE", "scan": true, "enc": "AES256",
    "created": "2026-08-18T12:46:16Z" } ]
```

**Las tres lecturas que valen:**

1. **`findingSeverityCounts: {}` — cero CVEs.** Es la comprobación objetiva, y no la intuición, de
   que descartar la imagen de 2018 valió la pena. El escaneo de ECR mira los paquetes del sistema
   operativo de la imagen; sobre `nginx:alpine` actual no encontró nada.
2. **`imageManifestMediaType` es `manifest.v2+json`, no una lista.** El `--provenance=false`
   funcionó: sin él, buildx habría subido también un *attestation manifest*, y en la consola de ECR
   aparecería una segunda entrada con plataforma `unknown/unknown` al lado de la imagen real,
   escaneada por separado. Es de esas cosas que después no se saben explicar.
3. **`enc: AES256` sin haberlo declarado.** Confirma que omitir `encryption_configuration` fue
   correcto: el default ya cifra con clave gestionada por AWS.

**Nota de tamaño, con la unidad correcta**: 34.952.071 B = **33 MiB comprimidos** en ECR, contra los
112 MB que reporta `docker images` en local. Son dos medidas distintas — la de ECR es lo que viaja
por la red, la local es lo que ocupa el disco descomprimido. De esos 112 MB, solo **9,7 MB** son los
assets del juego; el resto es la base `nginx:alpine`. Contra los 54 MiB comprimidos de
`darmos/streetfighter`, la imagen propia es a la vez más chica y más nueva.

`CAPTURA PENDIENTE -- consola de ECR, repositorio sf-tf-workshop-lm: se tiene que ver la unica
imagen con tag latest, su digest, y la columna de vulnerabilidades del scan on push en cero`

---

### [Fase 5] — IAM: rol, dos attachments e instance profile

Config agregada: `iam.tf`, cuatro recursos. Sin outputs nuevos — nadie consume estos IDs (mismo
criterio que con el IGW y la route table en la Fase 2).

```bash
terraform fmt && terraform validate && terraform apply   # Plan: 4 to add
```

Extracto del `plan`, con los dos campos que importan:

```
  # aws_iam_role.instance will be created
  + resource "aws_iam_role" "instance" {
      + name                  = "role-ec2-tf-workshop-lm"
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = "sts:AssumeRole"
                      + Effect    = "Allow"
                      + Principal = { + Service = "ec2.amazonaws.com" }
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + path                  = "/"
    }

  # aws_iam_instance_profile.instance will be created
  + resource "aws_iam_instance_profile" "instance" {
      + name = "profile-ec2-tf-workshop-lm"
      + role = "role-ec2-tf-workshop-lm"
    }
```

**`managed_policy_arns = (known after apply)` es la prueba de que los attachments van por fuera.**
Terraform sabe que el atributo va a tener contenido pero no lo está gobernando: lo llenan los dos
`aws_iam_role_policy_attachment`. Si en cambio se hubiera declarado `managed_policy_arns` dentro del
rol, ahí figuraría la lista literal — y Terraform borraría en cada `apply` cualquier política
adjuntada por otro medio. Es **el mismo dilema exacto que las reglas de SG inline vs. separadas** de
la Fase 2, y se resuelve igual: recursos separados, y nunca mezclar los dos estilos sobre el mismo
rol.

**`role = "role-ec2-tf-workshop-lm"` es el NOMBRE, no el ARN.** Vale para el instance profile y para
los dos attachments. Poner el ARN es un error frecuente y el mensaje de AWS no es obvio.

Dos defaults que AWS pone y no se escribieron: `path = "/"` (la jerarquía de IAM, que casi nadie
usa) y `max_session_duration = 3600` — una hora, que es cada cuánto la instancia renueva por IMDS
las credenciales temporales del rol.

#### Verificación contra la API

```bash
ROLE=role-ec2-tf-workshop-lm
aws iam list-instance-profiles-for-role --role-name "$ROLE"
aws iam list-attached-role-policies     --role-name "$ROLE"
aws iam get-role                        --role-name "$ROLE"
aws iam list-role-policies              --role-name "$ROLE"
aws iam get-instance-profile --instance-profile-name profile-ec2-tf-workshop-lm
```

```json
// 1. el instance profile contiene el rol
[ { "profile": "profile-ec2-tf-workshop-lm",
    "arn": "arn:aws:iam::104981180500:instance-profile/profile-ec2-tf-workshop-lm",
    "roles": [ "role-ec2-tf-workshop-lm" ] } ]

// 2. politicas adjuntas
{ "AttachedPolicies": [
    { "PolicyName": "AmazonSSMManagedInstanceCore",       "PolicyArn": "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" },
    { "PolicyName": "AmazonEC2ContainerRegistryReadOnly", "PolicyArn": "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" } ] }

// 3. trust policy
{ "arn": "arn:aws:iam::104981180500:role/role-ec2-tf-workshop-lm",
  "created": "2026-08-18T13:14:48Z",
  "maxSession": 3600,
  "trust": { "Version": "2012-10-17",
             "Statement": [ { "Effect": "Allow",
                              "Principal": { "Service": "ec2.amazonaws.com" },
                              "Action": "sts:AssumeRole" } ] } }

// 4. politicas inline
{ "PolicyNames": [] }

// 5. instance profile
{ "arn": "arn:aws:iam::104981180500:instance-profile/profile-ec2-tf-workshop-lm",
  "id": "AIPARQ4K5WBKHX6MIHWCV",
  "roles": [ "role-ec2-tf-workshop-lm" ] }
```

**Por qué la verificación 1 es la que realmente importa.** Es la única que prueba la relación que
EC2 va a consumir en la Fase 6. Un rol perfecto y un instance profile perfecto pero **sin la
asociación entre ambos** dan una instancia que arranca sin credenciales, con un `user_data` que
falla en el `docker pull` y sin ningún error que apunte a IAM. Las otras cuatro consultas se ven
lindas y no prueban eso.

**`PolicyNames: []` confirma la elección de estilo**: los attachments adjuntan políticas
*gestionadas*, no dejan copias inline dentro del rol. Si mañana alguien agrega una política a mano
por consola, va a aparecer en `list-attached-role-policies` y **Terraform no la va a borrar**, que
es justamente el comportamiento que se eligió.

**El prefijo del ID dice el tipo de objeto.** `AIPARQ4K5WBKHX6MIHWCV` — `AIPA` es instance profile,
igual que `AIDA` es usuario IAM (visto en el `sts get-caller-identity` de la Fase 0) y `AROA` un
rol. Sirve cuando aparece un ID suelto en un log de CloudTrail y no hay contexto.

#### La consecuencia de diseño de `AmazonSSMManagedInstanceCore`

Esa política es lo que habilita Session Manager, y por eso **el SG de la Fase 2 no tiene ninguna
regla en el puerto 22 y no hay key pair en ningún lado del proyecto**. El agente de SSM sale hacia
los endpoints del servicio usando la regla de egress, y la sesión entra por ese canal ya
establecido. No hace falta abrir ningún puerto de entrada.

Es un buen ejemplo de una decisión de IAM que determina la superficie de red: el permiso reemplaza
a un puerto abierto.

`CAPTURA PENDIENTE -- consola de IAM, rol role-ec2-tf-workshop-lm: pestana Permissions con las dos
politicas gestionadas, y pestana Trust relationships con el principal ec2.amazonaws.com`

---

### [Fase 6] — EC2 con user_data: del `.tftpl` al HTTP 200 desde internet

Config agregada: `scripts/user-data.sh.tftpl`, `compute.tf`, 4 variables (`instance_type`,
`image_tag`, `host_port`, `container_port`) y 2 outputs (`instance_id`, `instance_public_ip`).

#### Paso previo: renderizar la plantilla ANTES de tocar AWS

La verificación más rentable de toda la fase, y no cuesta nada:

```bash
echo 'templatefile("scripts/user-data.sh.tftpl", {
  region = "us-east-1", registry = "104981180500.dkr.ecr.us-east-1.amazonaws.com",
  ecr_url = "104981180500.dkr.ecr.us-east-1.amazonaws.com/sf-tf-workshop-lm",
  image_tag = "latest", container_name = "sf", host_port = 80, container_port = 80 })' \
  | terraform console
```

Ejercita exactamente el mismo código que va a correr el `apply`, en local y sin crear nada.
**Encontró dos errores, y ninguno de los dos habría dado un mensaje útil desde una instancia:**

1. **Los comentarios del propio script rompían la plantilla.** El archivo tenía, dentro de líneas
   que empiezan con `#`, las secuencias de interpolación y de directiva escritas literalmente para
   explicarlas. **Terraform no distingue código de comentario**: el `#` es de bash, no de la
   plantilla. Iba a intentar interpolar una variable inexistente y a leer una directiva inválida.
   El `templatefile()` habría fallado en el `plan`. Se resolvió describiendo la sintaxis con
   palabras en lugar de mostrarla.
2. **El `docker login` apuntaba al repositorio en vez de al registry.** `repository_url` incluye el
   path (`.../sf-tf-workshop-lm`), y `docker login` espera solo el host. En el push manual de la
   Fase 4 estaba bien —`REG` para el login, `ECR` para el tag— y al pasarlo a plantilla se
   mezclaron. Este solo se ve **leyendo el render**, no el fuente. Se corrigió pasando el host como
   variable aparte, calculada en HCL:

   ```hcl
   registry = split("/", aws_ecr_repository.game.repository_url)[0]
   ```

   Se descartó recortarlo en bash: la sintaxis de recorte de shell choca con la de Terraform y
   habría que escaparla, y la lógica se lee mejor en HCL.

#### El choque de sintaxis de `templatefile()` con un script de shell

| Secuencia | Quién la interpreta | Qué hacer si es literal |
|---|---|---|
| interpolación (dólar + llave) | **Terraform** | duplicar el dólar |
| directiva (porcentaje + llave) | **Terraform** | duplicar el porcentaje |
| sustitución de comando `$(...)` | solo bash | nada, pasa intacta |

Terraform solo mira esas dos aperturas. Por eso los `$(date -u ...)` del script pasan sin tocarse,
pero el `-w` de `curl` con `%{http_code}` **habría roto el `templatefile()`**: hay que duplicar el
porcentaje. Verificado en el render, donde baja correctamente a `%{http_code}`.

#### Chequeo obligatorio de CRLF (el riesgo abierto desde la Fase 0)

```bash
file scripts/user-data.sh.tftpl
grep -c $'\r' scripts/user-data.sh.tftpl
head -c 20 scripts/user-data.sh.tftpl | od -c
bash -n scripts/user-data.sh.tftpl
```

```
scripts/user-data.sh.tftpl: Bourne-Again shell script, ASCII text executable
CR encontrados: 0
0000000   #   !   /   b   i   n   /   b   a   s   h  \n   #       -   -
sintaxis OK
```

Sin `CRLF line terminators` en la salida de `file`, cero retornos de carro, y el `od -c` muestra
`\n` justo después del shebang. `.gitattributes` línea 11 (`*.tftpl text eol=lf`) más el
`.editorconfig` sostienen las dos mitades del problema. **Riesgo de `DISENO.md` §6 cerrado con
evidencia.**

Bonus: `bash -n` valida la sintaxis del script **sin ejecutarlo**, y funciona igual sobre el
`.tftpl` sin renderizar, porque las interpolaciones son sintácticamente expansiones de parámetro
válidas para bash.

#### El riesgo del SSM Agent, disuelto en vez de mitigado

`DISENO.md` §6 anticipaba: *"si el paquete `amazon-ssm-agent` no existe, `yum install` falla y
**tampoco instala Docker**"*, con la mitigación de separar en dos `yum install`.

Verificado contra la doc de AWS ("Find AMIs with the SSM Agent preinstalled"): **AL2023 lo trae
preinstalado**. Textual — *"you'll likely find that the SSM Agent is already installed: … Amazon
Linux 2023 (AL2023)"*, con la advertencia de verificar igual. Así que el script no lo instala: lo
habilita y comprueba con `systemctl enable --now` + `systemctl is-active`. El escenario de fallo
desaparece porque desaparece el `install`.

#### `plan` y campos clave

```
Plan: 1 to add, 0 to change, 0 to destroy.

+ ami                         = "ami-02b3d83d84b07786d"
+ instance_type               = "t3.micro"
+ subnet_id                   = "subnet-0033c17b9c7ec238c"
+ iam_instance_profile        = "profile-ec2-tf-workshop-lm"
+ user_data_replace_on_change = true
+ http_tokens                 = "required"
+ volume_type                 = "gp3"    encrypted = true
```

#### Verificación desde afuera

```bash
aws ec2 describe-instances --instance-ids i-038459aacc0d1e104
aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=i-038459aacc0d1e104"
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-038459aacc0d1e104"
curl -sS -o /dev/null -w '%{http_code} %{size_download}B %{time_total}s\n' http://3.234.229.254/
```

```json
{ "state": "running", "type": "t3.micro", "az": "us-east-1a",
  "privIP": "10.0.1.217", "pubIP": "3.234.229.254",
  "profile": "arn:aws:iam::104981180500:instance-profile/profile-ec2-tf-workshop-lm",
  "imds": "required", "launch": "2026-08-18T13:34:27Z" }

{ "id": "vol-04d558ac501e8f649", "type": "gp3", "size": 8, "enc": true,
  "kms": "arn:aws:kms:us-east-1:104981180500:key/b6061ea6-87f4-4eb9-9557-369729891ccb" }

{ "id": "i-038459aacc0d1e104", "ping": "Online", "agent": "3.3.4624.0",
  "platform": "Amazon Linux", "version": "2023", "lastPing": "2026-08-18T13:37:17Z" }
```

```
raiz:        HTTP 200  1389B  en 0.355574s
ken.js:      HTTP 200  8377B
ken.png:     HTTP 200  120943B
git leak:    HTTP 404
Server: nginx/1.31.3
```

**`PingStatus: Online` es la verificación de mayor densidad de toda la fase.** Prueba de una sola
vez tres cosas independientes: que el instance profile llegó a la instancia, que el rol tiene
`AmazonSSMManagedInstanceCore`, y que hay salida a internet por el egress del SG. Si eso está en
verde, IAM y red están descartados como causa de cualquier otro problema.

El `404` en `/.git/config` confirma en producción lo que se había verificado en local: el
`.dockerignore` dejó el repositorio afuera de la imagen.

#### Verificación desde adentro, sin abrir sesión

`aws ssm start-session` necesita una terminal interactiva, pero **`send-command` no**, así que sirve
para inspeccionar la instancia desde un script:

```bash
aws ssm send-command --instance-ids i-038459aacc0d1e104 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker ps","cloud-init status --long","tail -25 /var/log/user-data.log"]'
aws ssm get-command-invocation --command-id <id> --instance-id <id>
```

```
{ "status": "Success", "rc": 0 }

===== DOCKER PS =====
sf | 104981180500.dkr.ecr.us-east-1.amazonaws.com/sf-tf-workshop-lm:latest | Up 3 minutes | 0.0.0.0:80->80/tcp, :::80->80/tcp

===== CURL LOCAL =====
local: HTTP 200

===== CLOUD-INIT =====
status: done
time: Tue, 18 Aug 2026 13:35:48 +0000
detail:
DataSourceEc2

===== ULTIMAS LINEAS DEL USER-DATA LOG =====
Digest: sha256:9dd22a3cef18c5c93eb17d79d4a008d748ea32396f96625d1729421f44b8e6e9
Status: Downloaded newer image for 104981180500.dkr.ecr.us-east-1.amazonaws.com/sf-tf-workshop-lm:latest
+ docker rm -f sf
+ docker run -d --name sf --restart unless-stopped -p 80:80 104981180500.dkr.ecr.us-east-1.amazonaws.com/sf-tf-workshop-lm:latest
a7f050feb3d32d8556293b51e879d3ef2695f5ff31fe67956a369938a331df86
+ sleep 3
+ docker ps
+ curl -sS -o /dev/null -w 'health local: HTTP %{http_code}\n' http://localhost:80/
health local: HTTP 200
++ date -u +%Y-%m-%dT%H:%M:%SZ
+ echo '== user_data termina OK: 2026-08-18T13:35:48Z =='
== user_data termina OK: 2026-08-18T13:35:48Z ==

===== ERRORES EN EL LOG =====
SIN-ERRORES

===== SERVICIOS =====
active
active
```

**Las tres lecturas que valen:**

1. **`== user_data termina OK ==` es la verificación entera, en una línea.** Con `set -e` activo, el
   script muere en el primer comando que devuelva distinto de cero. Que la última línea haya salido
   significa que **todos** los comandos anteriores devolvieron cero. No hace falta auditar el log:
   alcanza con comprobar que el `echo` final está. Es la razón concreta por la que conviene cerrar
   todo `user_data` con un marcador de fin.
2. **El log tiene la traza de `set -x`** (`+ docker run -d --name sf ...`). Si algo hubiera fallado,
   el log diría en qué comando exacto murió, no solo que murió. Esa es la diferencia entre
   diagnosticar y adivinar cuando el síntoma aparece a tres capas de la causa.
3. **El digest que bajó la instancia es idéntico al que se pusheó desde la notebook**
   (`sha256:9dd22a3c…f44b8e6e9`). Cierra la cadena de trazabilidad completa: fuente en GitHub →
   `docker build` local → push a ECR → `docker pull` de la EC2 → HTTP 200 desde internet.

**Tiempo total del arranque**: instancia lanzada `13:34:27`, `user_data` terminado `13:35:48` — **81
segundos** para instalar Docker, autenticarse contra ECR, bajar 33 MiB y levantar el contenedor.
Dato importante de operación: el `apply` de Terraform vuelve mucho antes, cuando AWS reporta
`running`. Entre que el `apply` dice "listo" y el juego responde hay más de un minuto, y eso **no
es un fallo**.

`CAPTURA PENDIENTE -- el juego cargado en el navegador contra la IP publica, con Ken y Guile en
pantalla y la tabla de controles visible`

`CAPTURA PENDIENTE -- consola de EC2, instancia i-038459aacc0d1e104, pestana Details: se tienen que
ver el IAM Role profile-ec2-tf-workshop-lm y IMDSv2 = Required`

---

### [Fase 7] — Registro A en Route53: del `plan` al juego resolviendo por nombre

**El `plan`, y las tres cosas que confirma antes de aplicar:**

```
  # aws_route53_record.game will be created
  + resource "aws_route53_record" "game" {
      + allow_overwrite = (known after apply)
      + fqdn            = (known after apply)
      + id              = (known after apply)
      + name            = "sf.luccamedina.ownboarding.teratest.net"
      + records         = [
          + "3.234.229.254",
        ]
      + ttl             = 60
      + type            = "A"
      + zone_id         = "Z0909248Q51XTVKXPOG"
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

1. **`name` aparece sin punto final.** En el HCL se escribió
   `"${var.game_name}.${data.aws_route53_zone.main.name}"`, y el atributo `name` del data source
   **viene con punto final**, así que la interpolación produce literalmente
   `sf.luccamedina.ownboarding.teratest.net.`. Terraform lo normaliza antes de guardarlo. Que el
   `plan` lo muestre ya normalizado es la prueba de que no va a haber diff perpetuo entre lo escrito
   y lo almacenado.
2. **`records` está resuelto, no `(known after apply)`.** La instancia ya existía y no se toca: el
   registro se cuelga de la IP que ya estaba en el estado.
3. **`0 to change, 0 to destroy`** con el data source de la AMI resolviendo `ami-02b3d83d84b07786d`
   — o sea, la AMI que el data source devuelve hoy es la misma con la que se creó la instancia. Ver
   la nota de §9 sobre por qué esto es suerte y no diseño.

**El `apply`:**

```
aws_route53_record.game: Creating...
aws_route53_record.game: Still creating... [00m10s elapsed]
aws_route53_record.game: Still creating... [00m21s elapsed]
aws_route53_record.game: Still creating... [00m31s elapsed]
aws_route53_record.game: Creation complete after 35s [id=Z0909248Q51XTVKXPOG_sf.luccamedina.ownboarding.teratest.net_A]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

**35 segundos para crear un registro DNS** llama la atención al lado de los recursos de red, que
son instantáneos. No es lentitud de la API: el provider **espera a que el change set pase a
`INSYNC`**, es decir, a que Route53 confirme que la modificación se propagó a sus cuatro
servidores autoritativos. Cuando el `apply` vuelve, el registro no está "creado y ya va a
propagar": está propagado.

El `id` tampoco es un ID de AWS. Es un identificador compuesto que arma el provider —
`<zone_id>_<nombre>_<tipo>` — porque la API de Route53 no le da identidad propia a un registro:
los `ResourceRecordSet` se direccionan justamente por esa terna. Por eso mismo el
`set_identifier` es obligatorio cuando hay routing policies: sin él, dos registros con el mismo
nombre y tipo colisionarían en el mismo `id`.

**La verificación, en el orden en que hay que hacerla:**

```bash
dig +short NS luccamedina.ownboarding.teratest.net
ns-1521.awsdns-62.org.
ns-169.awsdns-21.com.
ns-1930.awsdns-49.co.uk.
ns-793.awsdns-35.net.

# contra el NS autoritativo, salteando cualquier cache intermedia
dig +short A sf.luccamedina.ownboarding.teratest.net @ns-1521.awsdns-62.org.
3.234.229.254

# contra el resolver del sistema
dig +short A sf.luccamedina.ownboarding.teratest.net
3.234.229.254

curl -sS -o /dev/null -w "http_code=%{http_code} ip=%{remote_ip} tiempo=%{time_total}s\n" \
  http://sf.luccamedina.ownboarding.teratest.net
http_code=200 ip=3.234.229.254 tiempo=0.987992s
```

**Por qué primero el NS autoritativo y después el resolver.** Si uno consulta el nombre *antes* de
crearlo, el `NXDOMAIN` que devuelve Route53 **también se cachea**, con la duración del campo
`minimum` del registro SOA de la zona. Es el *negative caching* de la RFC 2308. El síntoma es
desconcertante: el registro existe en la consola de Route53, `terraform state show` lo muestra, y
`dig` sigue diciendo que no existe durante minutos. Preguntándole directo al NS autoritativo se
esquiva toda cache y se separa "el registro no está creado" de "mi resolver todavía se acuerda de
que no existía". Acá los dos coincidieron, así que no hubo caching negativo que esperar.

`curl -w` con `%{remote_ip}` cierra el círculo en un solo comando: dice a la vez que el DNS
resolvió, **a qué IP** resolvió, y que esa IP contestó 200. Un `curl` a secas confirmaría lo
primero y lo último pero dejaría abierta la pregunta de si estaba pegándole a la instancia
esperada.

**Outputs finales del proyecto:**

```
al2023_ami_id = "ami-02b3d83d84b07786d"
al2023_ami_name = "al2023-ami-2023.12.20260817.0-kernel-6.1-x86_64"
ecr_repository_url = "104981180500.dkr.ecr.us-east-1.amazonaws.com/sf-tf-workshop-lm"
game_url = "http://sf.luccamedina.ownboarding.teratest.net"
instance_id = "i-038459aacc0d1e104"
instance_public_ip = "3.234.229.254"
instance_security_group_id = "sg-0b1c39e081bc25b04"
main_route53_zone_arn = "arn:aws:route53:::hostedzone/Z0909248Q51XTVKXPOG"
main_route53_zone_id = "Z0909248Q51XTVKXPOG"
main_route53_zone_name = "luccamedina.ownboarding.teratest.net"
private_subnet_id = "subnet-03eb6819b955061da"
public_subnet_id = "subnet-0033c17b9c7ec238c"
vpc_id = "vpc-09b6544aea696e9dd"
```

`CAPTURA PENDIENTE -- el juego cargado en el navegador contra
http://sf.luccamedina.ownboarding.teratest.net, con la barra de direcciones visible mostrando el
nombre de dominio y no la IP`

`CAPTURA PENDIENTE -- consola de Route53, hosted zone luccamedina.ownboarding.teratest.net,
listado de registros: se tiene que ver el A de sf apuntando a 3.234.229.254 con TTL 60`

---

## 3. Troubleshooting real

Un bloque por problema **realmente ocurrido**. No hipotéticos.

### La instalación de Terraform por `apt` se cuelga sin devolver ningún error

- **Fase**: 0

- **Síntoma**: el comando de instalación oficial de HashiCorp lanzado desde Claude Code no
  terminó nunca. No hubo mensaje de error: el proceso superó el timeout de 120s y quedó en
  background, y el archivo de salida capturada quedó **completamente vacío** (0 bytes).

  ```
  wsl -d Ubuntu -- bash -lc 'wget -qO- https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && ...'
  ```

  ```
  Command did not complete within its 120s timeout and was moved to the background
  ```

- **Hipótesis descartadas**:
  - *Repo de HashiCorp sin soporte para Ubuntu 26.04 "resolute"*: descartada **antes** de correr
    nada — `curl -o /dev/null -w '%{http_code}' https://apt.releases.hashicorp.com/dists/resolute/Release`
    devolvió `HTTP 200`, o sea que el paquete existe.
  - *Falta de dependencias (`wget`, `gpg`, `lsb_release`)*: descartada, las tres estaban en
    `/usr/bin`, verificado con `command -v`.
  - *Red / DNS caídos en WSL*: descartada, las descargas por `curl` a `apt.releases.hashicorp.com`
    y `api.releases.hashicorp.com` funcionaban en la misma shell.
  - *Instalación a medias que dejó el sistema inconsistente*: descartada revisando el estado —
    ni `/usr/share/keyrings/hashicorp-archive-keyring.gpg` ni `/etc/apt/sources.list.d/hashicorp.list`
    llegaron a existir. Se colgó en el **primer** `sudo` de la cadena.

- **Causa raíz**: los comandos lanzados por Claude Code corren **sin TTY y con stdin
  desconectado**. `sudo` no tiene password cacheada, escribe el prompt
  `[sudo] password for lucca:` directo al terminal (no a stdout, por eso el archivo de salida
  quedó vacío) y se bloquea esperando una entrada que estructuralmente no puede llegar. No es
  un error del comando: el comando es correcto y funcionaría en una terminal interactiva.

- **Fix aplicado**: se cambió el método de instalación por uno que **no requiere root**: binario
  oficial desde `releases.hashicorp.com` desempaquetado en `~/.local/bin`. Se mantuvo el mismo
  nivel de garantía que da `apt` verificando a mano lo que el gestor de paquetes verifica solo:

  ```bash
  curl -sSLO https://releases.hashicorp.com/terraform/1.15.8/terraform_1.15.8_linux_amd64.zip
  curl -sSLO https://releases.hashicorp.com/terraform/1.15.8/terraform_1.15.8_SHA256SUMS
  curl -sSLO https://releases.hashicorp.com/terraform/1.15.8/terraform_1.15.8_SHA256SUMS.sig
  curl -sSL  https://www.hashicorp.com/.well-known/pgp-key.txt -o hashicorp.asc
  gpg --import hashicorp.asc && gpg --verify terraform_1.15.8_SHA256SUMS.sig terraform_1.15.8_SHA256SUMS
  sha256sum --check --ignore-missing terraform_1.15.8_SHA256SUMS
  unzip -o terraform_1.15.8_linux_amd64.zip -d ~/.local/bin
  ```

  ```
  gpg: Good signature from "HashiCorp Security (hashicorp.com/security) <security@hashicorp.com>"
  terraform_1.15.8_linux_amd64.zip: OK
  Terraform v1.15.8
  on linux_amd64
  ```

  **Sub-problema encontrado en el mismo fix**: tras instalar, `terraform` no resolvía —
  `/home/lucca/.local/bin NO esta en PATH de esta shell`. Causa: `~/.profile` de Ubuntu agrega
  ese directorio al PATH *solo si ya existe* (`if [ -d "$HOME/.local/bin" ]`), y la evaluación
  ocurre al iniciar la shell — el directorio se creó recién durante la instalación. Se resolvió
  solo al abrir una shell de login nueva; no hizo falta editar ningún dotfile. Verificado:
  `command -v terraform` → `/home/lucca/.local/bin/terraform`.

- **Lección**: cuando un comando se cuelga **sin producir ningún output**, el sospechoso número
  uno no es la red ni el paquete, es un **prompt interactivo esperando en un canal que nadie
  está mirando**. La ausencia total de salida es la pista: un fallo real casi siempre escribe
  algo. Generalizable a cualquier cosa que pida input — `sudo`, `ssh` con host key nueva,
  `git` pidiendo credenciales, y `terraform apply` sin `-auto-approve`, que va a pedir el
  `yes` exactamente igual. Corolario práctico: todo lo que necesite root en este workshop lo
  tengo que correr yo en una terminal real, o buscarle una vía sin privilegios.

- **Tiempo aproximado**: ~15 min (incluyendo los 2 min de timeout muerto).

---

### `terraform init` falla contra el registry por timeout, con red aparentemente sana

- **Fase**: 0

- **Síntoma**: al reinicializar tras agregar el bloque `backend "local" {}`, el `init` que había
  funcionado minutos antes falló:

  ```
  Error: Failed to query available provider packages

  Could not retrieve the list of available versions for provider hashicorp/aws:
  could not query provider registry for registry.terraform.io/hashicorp/aws:
  the request failed after 2 attempts, please try again later: Get
  "https://registry.terraform.io/v1/providers/hashicorp/aws/versions":
  net/http: request canceled (Client.Timeout exceeded while awaiting headers)
  ```

- **Hipótesis descartadas**:
  - *Registry caído*: descartada, `curl` al mismo endpoint devolvía `HTTP 200`.
  - *DNS roto en WSL*: descartada, `getent hosts` resolvía y `time_namelookup` era ~0,1s.
  - *Problema de IPv6* (primera hipótesis, y era razonable): `getent hosts` devolvía **solo
    direcciones IPv6** y `ip -6 route show default` estaba **vacío** — o sea, registros AAAA sin
    ruta IPv6. Encajaba con el patrón clásico de "intenta IPv6, espera, cae a IPv4". Se descartó
    midiendo: forzando `curl -4` el tiempo total era **igual** (~3,3s) que sin forzar, así que la
    penalidad no venía de ahí. `curl -6` fallaba en 112 ms, demasiado rápido para explicar 9s.

- **Causa raíz**: el desglose de tiempos de `curl` la aisló:

  ```
  dns 0.10s | tcp 0.15s | tls 3.03s | total 3.32s
  ```

  DNS y TCP normales; el **handshake TLS** se come todo, y en la primera medición llegó a ~9,3s.
  El cliente de registry de Terraform tiene un timeout por defecto de **10s** y hace 2 intentos,
  así que quedaba justo en el borde: a veces entraba, a veces no. No era un fallo determinista,
  era una carrera contra el timeout.

- **Fix aplicado**: subir el timeout con la variable de entorno documentada del CLI.

  ```bash
  TF_REGISTRY_CLIENT_TIMEOUT=30 terraform init
  ```

  ```
  - Reusing previous version of hashicorp/aws from the dependency lock file
  - Using previously-installed hashicorp/aws v6.60.0
  Terraform has been successfully initialized!
  ```

  Nótese que **no volvió a descargar** el provider: el `.terraform.lock.hcl` ya fijaba
  `v6.60.0` y el binario estaba en caché. Es la demostración práctica de para qué sirve el lock.

- **Lección**: dos, y las dos generalizables.
  1. **La hipótesis más elegante no es la correcta por ser elegante.** Lo de IPv6 sin ruta era un
     hallazgo real y encajaba perfecto con el síntoma, pero medir lo desmintió en un comando.
     Un `curl -w` con el desglose `dns/tcp/tls/total` separa las cuatro etapas y dice cuál es la
     que duele, en vez de adivinar.
  2. **"Timeout" no es sinónimo de "no hay conectividad".** Acá había conectividad plena y el
     endpoint respondía 200; el problema era que respondía *más lento que el límite que alguien
     eligió*. Antes de tocar la red, vale preguntarse cuál es el límite y si se puede correr.

- **Tiempo aproximado**: ~20 min.

---

### `terraform apply` falla por plugins no instalados, con el `init` recién hecho y OK

- **Fase**: 1

- **Síntoma**: `terraform apply` corrido desde PowerShell en Windows, minutos después de un
  `init` exitoso y un `plan` verde:

  ```
  Error: Required plugins are not installed

  The installed provider plugins are not consistent with the packages selected
  in the dependency lock file:
    - registry.terraform.io/hashicorp/aws: there is no package for
      registry.terraform.io/hashicorp/aws 6.60.0 cached in .terraform\providers

  To download the plugins required for this configuration, run:
    terraform init
  ```

- **Hipótesis descartadas**:
  - *`init` incompleto o corrupto*: descartada, el `plan` inmediatamente anterior había leído
    los dos data sources sin problema.
  - *Versión del provider mal resuelta*: descartada, el lock fija `6.60.0` y es la que está
    instalada.
  - **La pista del mensaje**: `.terraform\providers` con **barra invertida**. El error lo estaba
    reportando un Terraform de Windows, no el de WSL.

- **Causa raíz**: el `apply` se corrió desde **PowerShell** y no desde WSL. Los plugins de
  provider son **binarios compilados por plataforma**, no código portable. El `init` se había
  hecho desde WSL, así que en `.terraform/providers/.../6.60.0/` existía únicamente el
  subdirectorio `linux_amd64`. El binario de Windows buscaba `windows_amd64` y no lo encontraba.

  Se confirma también en el lock file, que tiene **un solo hash `h1:`**:

  ```
  "h1:VF6oe4urgR2lRZuCAytMHvUZHtqcZU99TGw915LdCL0="
  ```

  Los 16 `zh:` son los checksums firmados que publica el registry para todas las plataformas,
  pero el `h1:` corresponde al paquete de **la plataforma que instaló el `init`**. Solo figuraba
  Linux, así que ni siquiera con el binario descargado habría validado en Windows.

- **Fix aplicado**: correr el `apply` desde WSL, sobre el mismo directorio:

  ```bash
  wsl -d Ubuntu --cd /mnt/c/Users/lucca/desktop/teracloud/terraform -- terraform apply
  ```

  **Descartado a propósito**: correr `terraform init` desde Windows. Habría funcionado, pero
  descarga otros ~840 MB y agrega un segundo `h1:` al lock file, ensuciando el diff. Si alguna
  vez hace falta que el repo funcione en las dos plataformas, la forma correcta es declararlo,
  en vez de que dependa de dónde se corrió `init` por casualidad:

  ```bash
  terraform providers lock -platform=linux_amd64 -platform=windows_amd64
  ```

- **Lección**: `.terraform/` **no es portable** — es caché de binarios específicos de un sistema
  operativo, y esa es la razón de fondo por la que va al `.gitignore` (no solo por su tamaño).
  Corolario para este repo, que vive en `/mnt/c` y es alcanzable desde las dos terminales: el
  directorio es compartido pero el toolchain no, así que **hay que ser consistente sobre desde
  dónde se ejecuta**. Y la pista estaba en el propio mensaje de error: una barra invertida en
  `.terraform\providers` delata qué binario habló.

- **Tiempo aproximado**: ~10 min.

---

### El `plan` de la Fase 2 aborta: `invalid value for name (cannot begin with sg-)`

- **Fase**: 2

- **Síntoma**: el `plan` planificó bien 6 de los 10 recursos y después cortó:

  ```
  Error: invalid value for name (cannot begin with sg-)

    with aws_security_group.instance,
    on network.tf line 60, in resource "aws_security_group" "instance":
    60:   name        = "sg-instance-${local.name}"
  ```

- **Causa raíz**: AWS **reserva el prefijo `sg-`** para los IDs de security group, así que ningún
  SG puede llamarse así. El nombre venía de aplicar la convención de nombres del `DISENO.md` §3
  (`sg-instance-tf-workshop-lm`) sin distinguir dos cosas distintas que se llaman igual: el
  argumento **`name`** (nombre real del objeto en AWS, con reglas de formato) y el tag **`Name`**
  (etiqueta libre, sin restricciones).

- **Fix aplicado**: `name = "instance-${local.name}"`, dejando el tag `Name = "sg-instance-${local.name}"`
  intacto. La convención visual se conserva donde importa —la consola muestra el tag— y el
  argumento restringido cede.

- **Detalle que vale la pena**: el error lo tiró **`plan`, no `apply`**, y sin haber llamado a la
  API de AWS. Es una validación que el provider trae escrita adentro, y por eso los 6 recursos
  anteriores sí llegaron a planificarse: Terraform valida y planifica recurso por recurso, y
  reporta el problema junto con el plan parcial en vez de abortar en seco. Un `validate` no lo
  había agarrado antes porque la expresión `"sg-instance-${local.name}"` recién tiene un valor
  concreto que revisar cuando se evalúan las variables, en `plan`.

- **Lección**: cuando un recurso tiene un argumento `name` **y** un tag `Name`, no son lo mismo y
  casi nunca tienen las mismas reglas. El `name` es un identificador con validaciones del servicio
  (longitud, prefijos reservados, unicidad por cuenta/región); el tag es texto libre. Aplicar una
  convención de nombres a ciegas sobre los dos campos es la forma rápida de encontrarse esto.

- **Tiempo aproximado**: ~3 min. Va igual a la bitácora, por debajo de la regla de los 10 minutos,
  porque la distinción `name` vs. tag `Name` se repite en ECR (Fase 4) y en IAM (Fase 5).

---

### `docker push` falla con `permission denied` sobre el socket, con el usuario ya en el grupo `docker`

- **Fase**: 4

- **Síntoma**: el `docker login` a ECR funcionó, y los dos comandos siguientes fallaron:

  ```
  Login Succeeded

  ERROR: permission denied while trying to connect to the Docker daemon socket at
  unix:///var/run/docker.sock: Head "http://%2Fvar%2Frun%2Fdocker.sock/_ping":
  dial unix /var/run/docker.sock: connect: permission denied

  permission denied while trying to connect to the Docker daemon socket at
  unix:///var/run/docker.sock: Post "http://%2Fvar%2Frun%2Fdocker.sock/v1.51/images/
  104981180500.dkr.ecr.us-east-1.amazonaws.com/sf-tf-workshop-lm/push?tag=latest":
  dial unix /var/run/docker.sock: connect: permission denied
  ```

- **Hipótesis descartada de entrada, y por el propio output**: *problema de permisos de AWS / del
  usuario IAM sobre ECR*. Es la lectura natural cuando se acaba de crear el repositorio y la
  palabra "permission denied" aparece justo después de un comando de `aws`. Pero **`Login
  Succeeded` sale primero**: `docker login` habla con el registry por HTTPS y escribe el token en
  `~/.docker/config.json` — **no necesita el daemon**. O sea que la autenticación contra ECR había
  funcionado. El `permission denied` lo emite Docker, sobre un **socket Unix local**, y no tiene
  nada que ver con IAM.

- **Hipótesis descartadas**:
  - *El usuario no está en el grupo `docker`*: descartada, `getent group docker` devuelve
    `docker:x:1001:lucca`.
  - *Docker Desktop no está corriendo o la integración WSL está apagada*: descartada, el socket
    existe y el daemon responde.
  - *El socket tiene permisos mal*: descartada, `srw-rw---- 1 root docker` es exactamente lo
    normal — lectura y escritura para el dueño (`root`) y para el grupo (`docker`).

- **Causa raíz**: **la lista de grupos de un proceso se fija al iniciar la sesión y no se
  reevalúa.** La terminal estaba abierta desde antes de que se activara la integración WSL de
  Docker Desktop; el grupo `docker` se creó y se agregó al usuario **después**. El shell siguió
  corriendo con la lista de grupos vieja, sin `docker`, así que el kernel le negó el acceso al
  socket. La marca de tiempo lo confirma: el socket es de las `12:42`, posterior a la apertura de
  la shell.

  Comparación de la misma shell contra una recién abierta:

  ```bash
  # en una shell NUEVA
  id
  ls -l /var/run/docker.sock
  docker version --format 'client={{.Client.Version}} server={{.Server.Version}}'
  ```

  ```
  uid=1000(lucca) gid=1000(lucca) groups=1000(lucca),4(adm),24(cdrom),27(sudo),
      30(dip),46(plugdev),100(users),1001(docker)

  srw-rw---- 1 root docker 0 Aug 18 12:42 /var/run/docker.sock

  client=28.3.2 server=28.3.2
  ```

  En la shell nueva aparece `1001(docker)` en `groups` y todo funciona. En la vieja, no.

- **Fix aplicado**: abrir una terminal nueva. El `build` y el `push` corrieron sin tocar nada más
  y sin `sudo`. Alternativas sin cerrar la sesión: `newgrp docker` o `exec su -l "$USER"`, que
  fuerzan una reevaluación de los grupos.

  **Descartado a propósito**: `sudo docker ...`. Habría funcionado y es lo primero que aparece al
  buscar el error, pero deja los archivos del build y `~/.docker/config.json` con dueño `root`, y
  el `docker login` ya hecho como usuario normal no aplicaría — o sea que arrastra un segundo
  problema para tapar el primero. También `chmod 666 /var/run/docker.sock`, que es peor: da
  control del daemon a cualquier usuario de la máquina, y el daemon corre como root.

- **Lección**: **es el mismo mecanismo que el `~/.local/bin` que no estaba en el `PATH` en la Fase
  0.** En los dos casos la configuración era correcta en el disco y el problema era que el proceso
  en ejecución tenía una foto vieja del entorno, tomada al arrancar. Regla práctica: cuando algo
  "está bien configurado pero no anda", comparar el proceso actual contra **una shell recién
  abierta** antes de tocar la configuración. Si en la nueva funciona, el problema es el estado
  heredado, no la config.

  Segunda lección, sobre lectura de errores: **"permission denied" no dice de quién.** Acá había
  dos sistemas de permisos en juego —IAM y el filesystem de Linux— y el mensaje mencionaba
  `unix:///var/run/docker.sock`, que ya decía cuál de los dos. El `Login Succeeded` inmediatamente
  anterior descartaba el otro. La pista estaba entera en el output, como la barra invertida de
  `.terraform\providers` en el troubleshooting de la Fase 1.

- **Tiempo aproximado**: ~5 min. Va a la bitácora, por debajo de la regla de los diez minutos,
  porque el patrón "el proceso tiene una foto vieja del entorno" ya apareció dos veces en este
  workshop y va a volver a aparecer.

---

### `Error acquiring the state lock`: un `plan` matado a mitad deja el lock huérfano en S3

- **Fase**: 5 (ocurrió mientras se planificaba el IAM, pero es un problema del backend de la Fase 3)

- **Síntoma**: un `terraform plan` que había funcionado minutos antes empezó a fallar, y el fallo
  además tardaba dos minutos en aparecer:

  ```
  rc=1
  Error: Error acquiring the state lock
  Error message: operation error S3: PutObject, https response error
  ```

  Detalle que casi lo hace invisible: el primer intento se lanzó con la salida filtrada por `grep`,
  así que **el error se descartó junto con el resto del output** y el comando devolvió cero líneas
  sin ninguna pista. Se vio recién al volver a correrlo guardando la salida completa a un archivo.

- **Causa raíz**: se lanzó un script con **dos `terraform plan` seguidos**, sabiendo que cada uno
  tarda cerca de un minuto contra el backend S3. El segundo tomó el lock y el proceso fue **matado
  antes de terminar**, al superarse el timeout de la herramienta que lo había lanzado. Terraform
  libera el lock al finalizar; si se lo mata, no lo libera. El objeto `.tflock` quedó en el bucket
  sin dueño, y todo `plan` posterior se quedó esperando hasta agotar su `-lock-timeout`.

  El historial de versiones del bucket lo reconstruye entero, porque el versioning conserva cada
  lock y cada delete marker:

  ```bash
  aws s3api list-object-versions --bucket tf-state-workshop-lm-104981180500 \
    --prefix tf-workshop/terraform.tfstate.tflock \
    --query '{versiones:Versions[].{mod:LastModified,size:Size},borrados:DeleteMarkers[].{mod:LastModified}}'
  ```

  ```
  12:25:12 -> 12:25:27   init -migrate-state    lock + unlock
  12:26:15 -> 12:26:25   plan                   lock + unlock
  12:44:37 -> 12:44:48   plan                   lock + unlock
  12:46:01 -> 12:46:19   apply del ECR          lock + unlock
  13:03:00 -> 13:03:11   plan                   lock + unlock
  13:03:21 -> (nada)     plan                   LOCK HUERFANO
  ```

  Y el contenido del objeto dice quién lo dejó y cuándo:

  ```json
  {"ID":"6e6c1970-8301-860b-8a1e-029b1bc14ec1","Operation":"OperationTypePlan","Info":"",
   "Who":"lucca@LUQUITA","Version":"1.15.8","Created":"2026-08-18T13:03:20.199973691Z",
   "Path":"tf-state-workshop-lm-104981180500/tf-workshop/terraform.tfstate"}
  ```

- **Verificaciones hechas ANTES de romper el lock** (esta parte es la que importa, `force-unlock`
  a ciegas es peligroso):

  | Chequeo | Comando | Resultado |
  |---|---|---|
  | ¿Hay algún Terraform vivo? | `pgrep -a terraform` | **ninguno** |
  | ¿Qué operación tenía el lock? | contenido del `.tflock` | `OperationTypePlan` — **no** un apply |
  | ¿Hace cuánto? | `Created` vs. hora actual | ~7 minutos, sin actividad |
  | ¿El estado está sano? | `list-objects-v2` | 26.197 B, última escritura 12:46:19 (el apply del ECR) |

  El segundo punto es el que baja el riesgo casi a cero: **un `plan` no escribe el estado.** Romper
  el lock de un `plan` muerto no puede corromper nada. El caso peligroso de `force-unlock` es el
  opuesto — un `apply` que **sigue corriendo** y al que se le saca el lock por abajo: ahí quedan dos
  procesos escribiendo el mismo objeto, que es exactamente lo que el lock existe para impedir.

- **Fix aplicado**:

  ```bash
  terraform force-unlock 6e6c1970-8301-860b-8a1e-029b1bc14ec1
  ```

  Pide confirmación interactiva (`yes`) por TTY. Después el `plan` volvió a correr normal y dio
  `4 to add`.

- **Lecciones**, tres:

  1. **El lock funcionó exactamente como tiene que funcionar.** No es una anécdota de que "se
     rompió algo": los `plan` posteriores **se negaron a correr** en vez de operar sobre un estado
     que creían disponible. Sin `use_lockfile` no habría habido error — habría habido dos procesos
     escribiendo el mismo objeto, que es peor y silencioso.
  2. **Nunca filtrar la salida de un comando que puede fallar.** El primer intento pasaba el
     `plan` por `grep` y el error se fue con el filtro, dejando cero líneas y ninguna pista.
     Guardar a archivo y filtrar sobre el archivo cuesta lo mismo y conserva la evidencia.
  3. **Un `plan` contra un backend remoto no es gratis ni instantáneo** — acá tarda cerca de un
     minuto entre adquirir el lock, refrescar 13 recursos contra la API y liberar. Encadenar dos en
     un mismo comando con timeout es pedir que uno muera con el lock tomado.

- **Cómo se habría evitado**: una sola corrida, salida a archivo, y filtros sobre el archivo.

  ```bash
  terraform plan -no-color > /tmp/plan.txt 2>&1; echo "rc=$?"
  grep '# aws_' /tmp/plan.txt
  grep -E 'Plan:|No changes|Error' /tmp/plan.txt
  ```

- **Tiempo aproximado**: ~12 min, casi todos gastados en dos timeouts de 120 s esperando un lock
  que nunca se iba a liberar.

---

## 4. Decisiones tomadas durante la ejecución

Las que no estaban en `DISENO.md` o que lo contradicen. Incluir explícitamente las que
cambiaron de opinión a mitad de camino.

| Fase | Decisión | Alternativa descartada | Por qué | ¿Contradice el diseño original? |
|---|---|---|---|---|
| 0 | Trabajar 100% en WSL Ubuntu 26.04, instalando Terraform ahí | Trabajar 100% en Windows instalando el AWS CLI ahí (Terraform ya estaba en Windows v1.15.8) | El entorno estaba partido: Terraform solo en Windows, AWS CLI solo en WSL. Unificar en WSL mantiene una sola shell para `plan` + verificación por CLI, respeta el entorno que ya venía usando, y evita el riesgo de CRLF del `user-data.sh.tftpl` que ya había mordido en un lab anterior | No — `DISENO.md` §1 ya asumía WSL; el diseño no había registrado que Terraform no estaba instalado ahí |
| 1 | Fijar la línea de kernel en el filtro de la AMI: `al2023-ami-2023.*-kernel-6.1-x86_64` | Dejar `kernel-*` y que `most_recent` eligiera la más nueva | Las tres líneas de kernel (6.1, 6.12, 6.18) del mismo build tienen **idéntico `CreationDate`**, al segundo. Con empate, `most_recent` no tiene criterio y el ganador depende del orden en que la API devolvió los resultados: no elige la más nueva, tira una moneda. Verificado en vivo — el `plan` de Terraform resolvió a kernel-6.1 mientras un `sort_by` del CLI sobre los mismos datos resolvía a kernel-6.18 | No — el diseño no especificaba el filtro |
| 1 | Filtro acotado con `al2023-ami-2023.` como prefijo | Patrón amplio tipo `al2023-ami-*x86_64*` | El punto después de `2023` es lo que excluye las variantes `minimal`, `ecs`, `ecs-gpu` y `ecs-neuron`. Con el patrón amplio hay 327 matches y la más reciente por fecha era `al2023-ami-ecs-neuron-hvm-...`: habría levantado sin error y con Docker preinstalado, o sea que el problema no se habría notado nunca | No |
| 1 | Output `al2023_ami_name` además del `id` | Solo el `id` | `ami-07a5b367e8dc8bd92` no es legible; el `name` dice qué build y qué línea de kernel se seleccionó realmente. Es el dato que va a la tabla de trazabilidad de la documentación final | No — agrega al diseño, no lo contradice |
| 0 | `.gitattributes` **y** `.editorconfig`, los dos | Solo `.gitattributes`, que era el reflejo inicial | Actúan en momentos distintos y ninguno cubre al otro: `.gitattributes` normaliza en `commit`/`checkout`, `.editorconfig` en el guardado del editor. `templatefile()` lee **el archivo del disco**, no el índice de Git, así que un `.tftpl` escrito con CRLF por el editor llega con retorno de carro al `user_data` aunque el repo lo tenga en LF | No — el diseño identificaba el riesgo de CRLF pero no la mitigación |
| 0 | `backend "local" {}` declarado explícitamente en vez de omitir el bloque | Dejar el backend local implícito (comportamiento idéntico) | Funcionalmente son equivalentes, pero el explícito hace que la migración de Fase 3 sea un diff de una línea (`"local"` → `"s3"`) en vez de la aparición de un bloque de la nada. Además Terraform recién entonces escribe `.terraform/terraform.tfstate` con el `hash` del backend, que es contra lo que compara para detectar el cambio y ofrecer migrar el estado | No — el diseño pedía backend local en Fase 0-2, no decía cómo expresarlo |
| 0 | `.terraform.lock.hcl` **se commitea** | Ignorarlo, como hace el enunciado del workshop | Lo zanjó el output del propio `terraform init`: *"Include this file in your version control repository so that Terraform can guarantee to make the same selections by default"*. Sin él, otro `init` puede resolver un provider distinto dentro de `~> 6.0` | Sí, contradice el enunciado — divergencia deliberada y documentada. Cierra el riesgo de `DISENO.md` §6 |
| 0 | `required_version = ">= 1.10"` (piso mínimo) en vez de `~> 1.10` | Restricción pesimista con techo en 2.0 | El requisito real es solo que `use_lockfile` necesita >= 1.10. Poner `< 2.0` afirmaría algo no verificado. El `~>` sí se mantiene en el provider (`~> 6.0`), porque ese lo instala `init` solo y sin aprobación humana | No |
| 0 | `region` y `default_tags` salieron a `variables.tf` ya en Fase 0 | Hardcodearlas en `providers.tf` y refactorizar después | Sale gratis hacerlo bien de entrada y evita un refactor posterior | No — `DISENO.md` §2 ya preveía `variables.tf`, solo que no en esta fase |
| 0 | Terraform instalado como binario en `~/.local/bin`, no por `apt` | Repo de HashiCorp vía `apt` (el método oficial recomendado) | El `apt` exige `sudo` y todo lo que se lanza desde Claude Code va sin TTY, así que la password no se puede tipear. El binario no necesita root y conserva la misma garantía verificando firma GPG + SHA256 a mano. Contra: las actualizaciones son manuales — irrelevante acá porque `required_version` en `versions.tf` pinea la versión igual | No — el diseño no fijaba método de instalación |
| 0 | Repo en `/mnt/c/Users/lucca/desktop/teracloud/terraform`, no en el home de WSL | Mover el repo a `~/` dentro de WSL (mejor performance de I/O) | Los archivos se editan desde Windows y se ejecuta desde WSL sobre el mismo path montado; mover el repo partiría el trabajo entre dos filesystems. El volumen de este lab no justifica el overhead de `/mnt/c` | No — el diseño no se pronunciaba |
| 0 | Commitear el borrado de los archivos del lab anterior en `main` | Reinicializar el repo desde cero descartando el historial | El historial deja registro de que la infra anterior existió y se eliminó a propósito; reinicializar lo perdía. Commit `4cb46a0`, 8 archivos, 273 líneas eliminadas | No |
| 2 | CIDR de subnets y AZ como variables (`public_subnet_cidr`, `private_subnet_cidr`, `public_subnet_az`, `private_subnet_az`) | Hardcodear `"10.0.1.0/24"` y `"us-east-1a"` en el recurso | Criterio adoptado: **todo valor que cambiaría entre entornos va a `variables.tf`**. `vpc_cidr` ya seguía esa regla desde la Fase 0; dejar las subnets hardcodeadas habría sido incoherente dentro del mismo archivo. Descartado también `data "aws_availability_zones"`: agrega un data source que el diseño no previó para un lab de una sola AZ útil | No — `DISENO.md` §3 fijaba los valores, no cómo expresarlos |
| 2 | Ruta a internet como bloque `route {}` **inline** dentro de `aws_route_table` | `aws_route` como recurso separado, por simetría con la decisión #4 de `CLAUDE.md` (reglas de SG separadas) | Parecen el mismo caso y no lo son. En el SG, los bloques inline **borran las reglas que agregó cualquier otro** y el provider v6 empuja a los recursos separados. En una route table que Terraform crea y posee entera, con una sola ruta, el inline es más legible y no tiene ese riesgo; `aws_route` gana cuando hay que agregar rutas a una tabla de otro módulo. Lo que nunca hay que hacer es mezclar los dos estilos en la misma tabla: se pisan en cada `apply` | No — el diseño no se pronunciaba sobre el estilo de la ruta |
| 2 | Regla de egress declarada explícitamente aunque "permitir todo" suene al default | Omitirla y confiar en el allow-all que AWS pone solo | La doc del provider lo dice al revés de lo que uno espera: *"By default, AWS creates an `ALLOW ALL` egress rule (...) Terraform will remove this default rule, and require you specifically re-create it"*. Sin la regla explícita el SG queda con **salida cero** | No — el diseño ya la listaba (recurso #10); acá se documenta *por qué* es obligatoria |
| 2 | SG con `name` fijo en vez de `name_prefix` | `name_prefix` + `create_before_destroy` | Cambiar el `name` fuerza reemplazo del SG, y AWS no deja borrar un SG en uso: con la EC2 adjunta (Fase 6) el reemplazo se traba. `name_prefix` + `create_before_destroy` es el patrón de producción. Acá el nombre sale de variables que no se van a tocar, así que el riesgo no se materializa | No |
| 2 | Outputs solo para VPC, las dos subnets y el SG | Exportar también IGW, route table y association | Un output existe para que alguien lo consuma: el humano que verifica, un comando, u otra fase. Los IDs de IGW/RT/association no los referencia nadie y su efecto se verifica mirando la ruta, no el ID. Un output que nadie lee es ruido en cada `apply` | No |
| 2 | Cambio de modalidad de trabajo: Claude escribe el HCL paso a paso explicando cada campo antes de pegarlo; yo aprendo revisando | Seguir escribiendo yo el HCL con Claude revisando (modalidad de las Fases 0-2) | Escribir a ciegas contra la doc frenaba el avance sin agregar entendimiento: el cuello de botella no era teclear HCL sino saber qué campos existen y cuáles son las trampas. La explicación *antes* de cada bloque, más el `fmt`/`validate` por paso, conserva el objetivo original (entender cada campo). Registrado en `CLAUDE.md` | Sí — contradice la regla "escribo yo el HCL, vos revisás" de `CLAUDE.md`, que queda reemplazada desde el 14-ago-2026 |
| 3 | `key = "tf-workshop/terraform.tfstate"`, con prefijo, en vez de la key pelada en la raíz del bucket | `key = "terraform.tfstate"` | Un bucket de estado normalmente hospeda varios estados (por proyecto, por entorno, por capa) y el prefijo es lo único que los separa. Acá hay uno solo, así que es previsión y no necesidad — pero es el campo **más caro de cambiar después**: cambiarlo hace que Terraform lea una key vacía, concluya que no existe nada y proponga recrear los 10 recursos mientras los actuales siguen vivos y huérfanos | No — el diseño no especificaba la key |
| 3 | `use_lockfile = true`, sin tabla de DynamoDB | `dynamodb_table` (el patrón clásico, y lo que muestra la mayoría del material) | El lock nativo de S3 usa escrituras condicionales (`If-None-Match`) y deja un objeto `<key>.tflock` al lado del estado. Un recurso menos que crear, que pagar y que destruir. `dynamodb_table` quedó deprecado en Terraform 1.11+ y el requisito real (>= 1.10) ya estaba fijado en `required_version` desde la Fase 0 | No — ya estaba en `CLAUDE.md` como parámetro del proyecto; acá se ejecuta |
| 3 | `encrypt = true` aunque el bucket ya tiene SSE-S3 por defecto desde la Fase 0 | Confiar en el cifrado por defecto del bucket | Son dos garantías distintas y viven en lugares distintos: una en la configuración del bucket (que alguien puede cambiar sin tocar el repo), la otra en el código versionado. El estado guarda secretos en texto plano; que la garantía esté escrita en el repo es lo que la vuelve auditable y revisable en un PR | No |
| 3 | No borrar el `terraform.tfstate` local después de migrar | Limpiarlo para "no dejar basura" | Terraform lo deja a propósito como respaldo del origen de la migración, y el `.gitignore` ya lo cubre. Es la única copia del estado previo si la migración hubiera salido mal. Se elimina recién en el cierre de la Fase 9 | No |
| 4 | Street Fighter II: **construir la imagen nosotros** desde el fuente `jkneb/street-fighter-css` + `nginx:alpine` | Retaggear y pushear `darmos/streetfighter`, que ya existía y funcionaba | Tres motivos, en orden de peso: (1) la imagen de tercero es de 2018 sobre **Debian stretch con nginx 1.13**, las dos EOL, y se iba a exponer en `0.0.0.0/0:80`; (2) el enunciado pide *buildear* y pushear a ECR — retaggear la imagen de otro saltea el ejercicio; (3) publisher desconocido con 101 pulls, sin auditar. Resultado medido: scan on push con **0 hallazgos** y 33 MiB comprimidos contra los 54 MiB de la de 2018 | No — el diseño dejaba la imagen "a definir" |
| 4 | Elección verificada abriendo las capas de la imagen candidata, no leyendo su descripción | Confiar en el nombre y la descripción del repositorio de Docker Hub | Las descripciones estaban vacías en casi todos los candidatos. Bajando y destarando las capas se confirmó qué servía cada uno y en qué puerto: `tertiaryinfotech/street-fighter-game` era **solo arm64** (no bootea en `t3.micro`), `appachey` era un `php -S` en 8082, `rmelamud` y `alinablankselina` eran ~400 MB de Node, `simeontchakarov` ASP.NET en 8080. Solo `darmos` servía estático en 80 | No |
| 4 | `.dockerignore` excluyendo `.git`, `scss`, `readme.md` y el propio `Dockerfile` | `COPY . /usr/share/nginx/html` a secas, como salió el primer Dockerfile | Sin él, nginx **sirve el `.git/` por HTTP**: 12,5 MB de packfiles desde los que se reconstruye el repo y su historial completo. Acá el fuente es público y no cambia nada, pero es el patrón exacto con el que se filtran credenciales en `.git/config` o en commits viejos. Verificado después del fix: `GET /.git/config` → **404** | No |
| 4 | `docker build --provenance=false` | Dejar el default de buildx | Buildx exporta por defecto un *attestation manifest* junto a la imagen y convierte el push en una manifest list. En ECR eso aparece como **una segunda entrada con plataforma `unknown/unknown`** al lado de la imagen real, y el escaneo la reporta aparte. Con el flag el manifest quedó `v2` simple. Verificado: `imageManifestMediaType = application/vnd.docker.distribution.manifest.v2+json` | No |
| 4 | `game_name` como variable, no string en el recurso | Escribir `"sf"` directo en `aws_ecr_repository.name` | Un solo valor alimenta dos puntas separadas por tres fases: el nombre del repo ECR (Fase 4) y el subdominio del registro DNS (Fase 7). Cambiar de juego es cambiar una línea. Sigue el criterio adoptado en Fase 2 | No |
| 4 | `encryption_configuration` **omitido** a propósito | Declararlo con `encryption_type = "AES256"` | El default ya es `AES256` con clave gestionada por AWS — verificado en el `describe-repositories` post-apply. Declarar un default sin cambiarlo agrega ruido al HCL y hace creer que hubo una decisión donde no la hubo. Si hiciera falta CMK propia sería `encryption_type = "KMS"` + `kms_key` | No |
| 5 | Trust policy escrita con `jsonencode({...})` | Heredoc con JSON crudo, o `data "aws_iam_policy_document"` | El heredoc es un string opaco: un error de sintaxis JSON recién aparece en el `apply`, contra la API. Con `jsonencode` el objeto es HCL, lo chequea `validate`, y las interpolaciones son normales. `aws_iam_policy_document` vale la pena cuando hay condiciones y statements múltiples — para una trust policy de cinco líneas agrega ceremonia sin ganancia | No — el diseño no fijaba la forma |
| 5 | `aws_iam_role_policy_attachment` como recursos separados | `managed_policy_arns` dentro del `aws_iam_role` | **Es el mismo dilema que las reglas de SG inline vs. separadas de la Fase 2, y se resuelve igual.** `managed_policy_arns` es exclusivo: Terraform saca del rol cualquier política adjuntada por fuera, en cada `apply`. El attachment separado convive. Se ve en el `plan`: con attachments, el rol muestra `managed_policy_arns = (known after apply)` — sabe que va a tener contenido pero no lo gobierna. Lo que nunca hay que hacer es mezclar los dos estilos sobre el mismo rol | No |
| 5 | Sin outputs para el rol ni el instance profile | Exportar sus ARNs "por las dudas" | Mismo criterio que en la Fase 2 con el IGW y la route table: un output existe para que alguien lo consuma. Estos IDs no los referencia ninguna fase posterior — la EC2 de la Fase 6 referencia el recurso directamente, no un output — ni ningún comando de verificación. Un output que nadie lee es ruido en cada `apply` | No |
| 5 | Session Manager en lugar de SSH, decidido desde IAM y no desde la red | Key pair + regla de ingress en el 22 | Es una decisión de IAM que **determina la superficie de red**: con `AmazonSSMManagedInstanceCore` el agente sale hacia los endpoints de SSM por la regla de egress y la sesión entra por ese canal ya establecido, así que no hace falta abrir ningún puerto de entrada ni distribuir una clave privada. Explica retroactivamente por qué el SG de la Fase 2 no tiene el 22 | No — `DISENO.md` ya listaba la política; acá se documenta la consecuencia |
| 6 | `user_data_replace_on_change = true` | Dejar el default `false` | Es el argumento que decide si la fase es frustrante. `cloud-init` ejecuta el `user_data` **solo en el primer arranque**: con el default, corregir el script actualiza el atributo en el estado, el `apply` reporta `1 changed`, y la instancia sigue corriendo el script viejo. Fallo silencioso y con confirmación de éxito. Con `true`, cambiar el script destruye y recrea, que es lo único que hace que un `user_data` nuevo se ejecute | No — el diseño no lo mencionaba |
| 6 | `metadata_options { http_tokens = "required" }` | El default `optional` | Con `optional`, IMDSv1 sigue habilitado: un `GET` sin token devuelve las credenciales del rol, y cualquier SSRF en la aplicación se convierte en robo de credenciales. La AMI declara `imds_support: v2.0`, pero eso es una propiedad de la imagen — el que manda es este campo de la instancia | No — agrega al diseño |
| 6 | `root_block_device` con `gp3` y `encrypted = true` | Dejar el default de la AMI | `encrypted` es `false` por defecto (verificado en la doc del provider) y el cifrado de EBS no tiene costo adicional. `gp3` es más barato y con mejor baseline que `gp2`. Tres líneas para no dejar un disco sin cifrar | Sí, agrega al diseño: `DISENO.md` §3 no preveía el bloque |
| 6 | El host del registry se calcula en HCL con `split()`, no recortando el string en bash | `$${ecr_url%%/*}` dentro del script | La sintaxis de recorte de shell choca con la de interpolación de Terraform y habría que escaparla, quedando ilegible. La lógica en HCL se lee mejor y se ve en el `plan`. Además el error original —hacer `docker login` contra el repositorio en vez del registry— solo se detectó **leyendo el render**, no el fuente | No |
| 6 | El SSM Agent **no** se instala: solo se habilita y verifica | Instalarlo, como preveía la mitigación de `DISENO.md` §6 | Verificado contra la doc de AWS: AL2023 lo trae preinstalado. El riesgo anotado —"si el paquete no existe, el `install` falla y tampoco instala Docker"— **desaparece porque desaparece el `install`**, que es mejor que mitigarlo separando comandos | Sí — reemplaza la mitigación planificada por una que elimina la causa |
| 6 | Renderizar la plantilla con `terraform console` antes de aplicar | Confiar en `validate` y descubrirlo en el `apply` | `validate` no evalúa `templatefile()` con valores concretos. El render local encontró dos errores: comentarios del script que rompían la plantilla, y el `docker login` apuntando al repositorio en vez del registry. El segundo **no se ve en el fuente**, solo en el render, y habría fallado dentro de una instancia ya lanzada | No — es método, no diseño |
| 7 | Registro `A` con `records` + `ttl`, no un bloque `alias` | `alias { name = ..., zone_id = ... }` | Un `alias` de Route53 solo puede apuntar a recursos de AWS que tengan nombre DNS propio —ALB, NLB, CloudFront, S3 website, API Gateway— y a otro registro de la misma zona. **No existe alias hacia una IP.** Como el destino es la IP pública cruda de una EC2, el tipo A con `records` es la única opción. La consecuencia se paga en la factura: las consultas a un A no-alias se cobran, las de un Alias hacia un recurso de AWS no | No — `DISENO.md` §3 ya preveía el registro A |
| 7 | `ttl = 60` | 300 (el valor típico) o 3600 | La instancia **no tiene Elastic IP**, y `user_data_replace_on_change = true` hace que cualquier cambio del script la reemplace y con ella la IP pública. Con TTL 3600, después de un reemplazo el juego queda inaccesible hasta una hora para quien ya lo hubiera resuelto. 60 s acota ese daño a un minuto. En producción el TTL alto es correcto justamente porque el destino es estable (ALB con Alias) | No — el diseño no fijaba el TTL |
| 7 | `allow_overwrite` **omitido**, quedando en su default `false` | Ponerlo en `true` "para que el apply nunca falle" | Con `false`, si el registro ya existiera creado a mano en la zona, el `apply` **falla** en vez de pisarlo en silencio. La doc del provider es explícita: *"This configuration is not recommended for most environments"*. Es exactamente la protección que uno quiere en una hosted zone compartida, donde otro registro `sf` podría ser de otra persona. Mismo criterio que en Fase 4 con `encryption_configuration`: no declarar un default salvo que se lo esté cambiando | No |
| 7 | El output `game_url` se arma con `aws_route53_record.game.fqdn`, no con una string a mano | `"http://${var.game_name}.${var.domain}"` interpolando las mismas variables | La string a mano describe lo que uno *cree* que creó; `fqdn` es lo que **Route53 efectivamente guardó**, leído del estado post-apply. Si el nombre se normalizara distinto de lo esperado, la string a mano seguiría mostrando la URL linda y equivocada. Además `fqdn` viene ya sin punto final, que es lo que un navegador necesita | No |
| 7 | El registro va sin `tags` | Agregar `tags = { Name = ... }` por coherencia con todos los demás recursos del repo | No es una decisión de estilo: **los `ResourceRecordSet` de Route53 no soportan tags**. Solo son taggables las hosted zones y los health checks. Es el primer recurso del proyecto donde los `default_tags` del provider no aplican, y conviene dejarlo escrito en el HCL para que no parezca un olvido en la revisión | No |

---

## 5. Lab vs. producción

Cada vez que algo se hace "porque es un lab", va acá. Base inicial en `DISENO.md` sección 8.

| Decisión (lab) | Por qué | En producción |
|---|---|---|
| Usuario IAM personal con `AdministratorAccess` y access keys estáticas de larga vida | Lo pide el enunciado del workshop. Verificado en Fase 0: política adjunta directa, sin permissions boundary y sin SCPs (cuenta standalone) — o sea, permiso total y sin ningún techo | OIDC federation desde el CI/CD hacia un rol con permisos mínimos por servicio; cero credenciales estáticas. Contradice de frente el criterio de OIDC del Workshop 5 |
| Cuenta AWS fuera de una organización, sin SCPs | Cuenta de lab individual | Cuenta miembro de una organización con SCPs como red de contención: restricción de regiones habilitadas, prohibición de borrar CloudTrail/logs, y bloqueo de acciones IAM privilegiadas fuera del pipeline |
| Las mismas access keys replicadas en `~/.aws` de WSL y de Windows (3 perfiles, misma key `...PD7H`) | Comodidad de tener las credenciales disponibles desde cualquiera de las dos shells | Credenciales de corta duración vía SSO / `assume-role`, nunca material estático duplicado en varios filesystems. Cada copia es una superficie más de la que se puede filtrar |
| Puerto 8080 abierto a `0.0.0.0/0` en el SG | Debug: si el juego no responde en 80, permite aislar si el problema es el contenedor o el mapeo `-p 80:<puerto>` del `docker run`. Con el mapeo bien hecho, la regla es innecesaria incluso en el lab | El puerto de la aplicación nunca se expone a internet. Solo 443 desde el ALB, y el tráfico al puerto de la app queda dentro del SG del backend, con `referenced_security_group_id` en vez de un CIDR |
| Egress abierto a todo destino (`ip_protocol = "-1"`, `0.0.0.0/0`) | La instancia necesita salir a ECR, a los repos de `yum` y a los endpoints de SSM, y enumerar esos destinos a mano en un lab no aporta | VPC endpoints (interface) para ECR, S3 y SSM, con egress restringido a esos endpoints y a `prefix_list_id` de S3. La instancia deja de necesitar salida a internet |
| SG con `name` fijo en vez de `name_prefix` + `create_before_destroy` | El nombre sale de variables que no se tocan durante el lab | `name_prefix` + `create_before_destroy`: un cambio de nombre en un SG adjunto a instancias se traba porque AWS no permite borrar un SG en uso |
| Tag `latest` mutable en ECR (`image_tag_mutability = "MUTABLE"`) | Permite corregir la imagen y volver a pushear `latest` sin cambiar nada del user_data. Con `IMMUTABLE` el segundo push falla | Tag inmutable por SHA del commit, `latest` inexistente. Con `latest` mutable no se puede saber qué versión está corriendo una instancia, y dos EC2 lanzadas con horas de diferencia pueden tener imágenes distintas con el mismo tag |
| `FROM nginx:alpine` sin fijar digest | Simplicidad, y que la base quede siempre al día durante el lab | `FROM nginx:alpine@sha256:...`. Es **el mismo problema que `most_recent = true` en el data source de la AMI**: un tag móvil hace que dos builds del mismo Dockerfile, con semanas de diferencia, produzcan imágenes distintas. Reproducibilidad y pin explícito, con actualización deliberada del digest |
| `force_delete = true` en el repositorio ECR | Sin esto el `terraform destroy` de la Fase 9 falla con `RepositoryNotEmptyException` y deja el destroy a medias | Sin `force_delete`: el borrado de un repositorio con imágenes tiene que ser una decisión explícita y no un efecto colateral de un `destroy`. Las imágenes son artefactos con trazabilidad, no basura recreable |
| Assets del juego (sprites, música) con copyright de Capcom, repo fuente sin licencia | Es un lab interno con una URL efímera que se destruye en la Fase 9 | Contenido propio o con licencia verificada. Publicar esto como producto es un problema legal, no técnico |
| Imagen construida y pusheada desde la notebook, con las access keys personales | Es el paso didáctico que pide el enunciado | Build y push desde el pipeline de CI/CD, con OIDC, tag = SHA del commit, y el registry como única fuente de artefactos desplegables |
| `AmazonEC2ContainerRegistryReadOnly` (política gestionada por AWS) en vez de una propia | Es la que pide el enunciado y evita escribir una política a mano en un lab | Da lectura sobre **todos** los repositorios de la cuenta, no solo el del juego, e incluye `ecr:GetAuthorizationToken` a nivel cuenta. En producción: política propia con `Resource` apuntando al ARN del repositorio concreto. Las políticas gestionadas de AWS son un punto de partida cómodo y casi nunca son de mínimo privilegio |
| Un solo rol para las dos responsabilidades (pull de ECR y acceso por SSM) | Alcance del lab: una instancia, un propósito | Separación por función, con roles distintos para el acceso operativo y para el consumo de artefactos. Acá cualquiera que consiga una sesión por SSM hereda también el permiso de lectura sobre todo ECR |
| IP pública directa, sin Elastic IP, y el registro DNS apuntando a ella | Simplicidad del lab | La IP cambia con cada `stop`/`start` y con cada reemplazo de la instancia — y `user_data_replace_on_change = true` hace que **cualquier cambio del script reemplace la instancia y por lo tanto la IP**. En producción: ALB con registro Alias, o al menos una EIP |
| `set -euxo pipefail` con `-x` en el `user_data` | El trace es lo que permite saber en qué comando exacto murió el script, cuando el síntoma aparece a tres capas de la causa | El trace puede filtrar valores sensibles pasados como argumento a un comando. Acá no pasa —el token de ECR viaja por un pipe, no por `argv`— pero en un script que reciba secretos por parámetro hay que desactivar `-x` en ese tramo |
| El contenedor corre como `root` dentro de la imagen `nginx:alpine` | Es el default de la imagen oficial y el lab no lo requiere | Usuario sin privilegios en el contenedor, `--read-only` en el filesystem, y `--cap-drop ALL` salvo lo indispensable |
| Sin health check ni reinicio automático más allá de `--restart unless-stopped` | Alcance del lab | Health check del orquestador que reemplace la tarea cuando deja de responder. `--restart` solo cubre que el proceso muera, no que se cuelgue respondiendo mal |
| Sin HTTPS: registro A directo a la IP y tráfico por el puerto 80 | El enunciado no pide TLS y no hay ALB donde terminarlo | Certificado de ACM en un ALB, listener 443 y redirect 80→443. Hoy el juego viaja en claro y el navegador lo marca como *Not secure*. Sin ALB no hay dónde poner el certificado: montar TLS en la propia instancia obligaría a renovar con certbot dentro del `user_data` |
| Registro A no-alias apuntando a una IP, en vez de Alias a un ALB | No hay ALB en el lab, y no existe Alias hacia una IP | El Alias no cobra las consultas y sigue solo al recurso, no a una dirección: la IP del ALB puede cambiar sin tocar el DNS. El registro A acopla el nombre a una IP concreta y hace del TTL un parámetro crítico |
| Subdominio creado en una hosted zone **compartida** de la empresa, con `allow_overwrite = false` como única protección | Es la zona que provee el onboarding | Zona delegada por proyecto o por entorno, con la política de IAM del rol de despliegue restringida a `route53:ChangeResourceRecordSets` sobre esa zona. Hoy, un error de nombre en `var.game_name` escribiría en la zona de todos, y el permiso de administrador no lo impide |

---

## 6. Conceptos nuevos de Terraform

Explicados en criollo, como se los contaría a alguien. Prioridad a lo contraintuitivo.

### Data source vs. resource, y por qué `most_recent` no es lo que parece

- **Qué es**: un `data` lee infraestructura que ya existe; un `resource` la crea y la administra.
  La diferencia queda escrita en el estado como `"mode": "data"` contra `"mode": "managed"`, y
  tiene consecuencias: `terraform destroy` no toca las entradas `data`, y un `apply` que solo
  tiene data sources reporta `0 added, 0 changed, 0 destroyed`.

- **Por qué importa**: es la forma de referirse a cosas que Terraform no administra sin tener que
  hardcodear IDs. La hosted zone ya existía en la cuenta: hardcodear `Z0909248Q51XTVKXPOG` habría
  funcionado igual, pero el data source documenta *de dónde sale* ese ID y sobrevive a que la
  zona se recree.

- **Lo contraintuitivo (esto es lo importante)**: `most_recent = true` **no garantiza un
  resultado determinista**. Ordena por `CreationDate` y se queda con el primero, pero AWS publica
  las tres líneas de kernel del mismo build con **el mismo timestamp exacto**:

  ```
  2026-08-03T17:39:25.000Z   ami-07a5b367e8dc8bd92   ...kernel-6.1-x86_64
  2026-08-03T17:39:25.000Z   ami-09ea3fdf5cd76c4a0   ...kernel-6.12-x86_64
  2026-08-03T17:39:25.000Z   ami-0bdc7d025135d7b49   ...kernel-6.18-x86_64
  ```

  Con empate no hay criterio: gana el que la API haya devuelto primero. Se comprobó en vivo —
  Terraform resolvió a kernel-6.1 y un `sort_by` del AWS CLI sobre exactamente los mismos datos
  resolvió a kernel-6.18. La conclusión práctica es que **el filtro tiene que ser lo bastante
  estrecho como para que `most_recent` no tenga que desempatar nada**.

- **Qué creía antes**: que con poner `owners = ["amazon"]` el data source de AMI ya estaba
  resuelto. `owners` evita que un tercero te inyecte una imagen, que es el riesgo grave, pero no
  evita elegir la variante equivocada **del mismo publicador**: con un patrón amplio la más
  reciente de las 327 era una `ecs-neuron`, que habría arrancado sin dar ningún error.

- **El segundo efecto, que muerde en la Fase 8**: `most_recent = true` significa que el ID puede
  cambiar solo cuando AWS publica un build nuevo. Como el argumento `ami` de `aws_instance` fuerza
  reemplazo, un `plan` corrido semanas después puede proponer destruir y recrear la instancia sin
  que haya cambiado una línea de código.

- **La alternativa que existe y no se usó acá**: AWS publica parámetros SSM que siempre apuntan a
  la última AMI (`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64`), leíbles con
  `data "aws_ssm_parameter"`. No hay patrón que escribir mal ni variante que se cuele. Se mantuvo
  `aws_ami` con filtros porque el punto didáctico del workshop es entender los filtros.

---

### El estado y el backend

- **Qué es**: el **estado** (`terraform.tfstate`) es la memoria de Terraform: un mapeo entre el
  nombre lógico del código y el ID real del recurso en AWS (`aws_vpc.main` → `vpc-0a1b2c3d`).
  El **backend** es, simplemente, el ajuste que define *dónde vive ese archivo* y *cómo se
  bloquea*. No es un recurso, no crea nada en AWS y no aparece en el `plan`.

- **Por qué importa**: sin estado, Terraform no tiene forma de saber que la VPC que declaraste
  ya existe — AWS no sabe cuál de sus VPCs es "la de Terraform". Si se pierde el estado, el
  siguiente `plan` propone crear todo de cero mientras lo viejo sigue existiendo y facturando,
  ahora huérfano y sin nadie que lo administre.

- **Qué creía antes**: que el backend era "algo que se configura", sin tener claro de dónde
  salía. La respuesta es que **no sale de ningún lado**: si no escribís bloque `backend`,
  Terraform aplica el default `local` y el estado va a un archivo al lado de los `.tf`. Escribir
  `backend "local" {}` no cambia el comportamiento, solo lo hace explícito.

- **Lo contraintuitivo (dos cosas)**:
  1. El bloque `backend` **no puede usar variables**. Nada de `bucket = var.bucket_name`. Se lee
     tan temprano en el arranque — antes que el provider, porque Terraform necesita saber dónde
     está su memoria antes de saber con qué nube habla — que las variables todavía no existen.
     Es de los poquísimos lugares donde hardcodear un string es lo correcto, y **contradice de
     frente la decisión #3 de `CLAUDE.md`** (nombres nunca hardcodeados). La excepción es
     estructural, no una concesión.
  2. El estado guarda **en texto plano** todo lo que Terraform sabe, incluidos secretos que hayan
     pasado por cualquier recurso. De ahí que `*.tfstate` vaya al `.gitignore` sin discusión, y
     que el bucket de estado lleve cifrado y block public access.

- **Paralelismo real**: el estado es a Terraform lo que el `.git` es a un repo — sin él, el
  directorio de trabajo sigue teniendo los archivos pero nadie sabe de dónde vinieron ni qué
  cambió. Y el backend es el equivalente a tener el repo solo en tu disco versus tenerlo en un
  remoto compartido: mismo contenido, pero uno se pierde con la máquina y no permite trabajar
  de a dos.

---

### `lineage` y `serial`: dos campos del estado que casi nadie mira, y qué significan de verdad

- **Qué son**: `serial` es un contador que sube en **cada escritura del archivo de estado**;
  `lineage` es un UUID que identifica al estado como *linaje*, o sea como historia continua de
  escrituras en un mismo lugar.

- **Lo primero contraintuitivo**: el `serial` **no cuenta `apply`s**. Después del `apply` de 10
  recursos de la Fase 2 quedó en **11**, no en 1. Terraform persiste el estado a medida que cada
  recurso termina, no una vez al final — que es también la razón por la que un `apply` interrumpido
  a la mitad no pierde lo que ya se creó.

- **Lo segundo contraintuitivo, y me costó una predicción equivocada**: el lineage **cambia al
  migrar de backend** si el destino está vacío, y eso es correcto. Verificado en el código de
  Terraform (`internal/states/remote/state.go`, `PersistState`): si el backend remoto no tiene
  snapshot previo, se genera un UUID nuevo y el serial arranca en 1. La migración de la Fase 3 dio
  `bb05f068-...` → `8976e38b-...` con serial 11 → 1, y no se perdió ni un recurso.

- **Para qué sirve entonces el lineage**: para detectar que **alguien reemplazó tu estado por otro
  distinto en el mismo lugar**, entre dos escrituras al mismo backend. Ese es el escenario que
  protege. Comparar lineages a través de una migración no prueba nada.

- **El invariante correcto para juzgar una migración de backend** son tres cosas, ninguna de las
  cuales es el lineage: (1) el conjunto de recursos en el destino, (2) que refresquen por sus IDs
  reales, y (3) que el `plan` diga `No changes`.

- **Qué creía antes**: que el lineage era el "número de serie" que probaba que el estado migrado
  era el mismo. Es al revés de útil de lo que parecía. La lección general: antes de usar un campo
  como criterio de aceptación, hay que saber **quién lo escribe y en qué momento** — si no, se está
  verificando una intuición, no un hecho.

---

### El lock de estado es un objeto de S3, y se puede leer

- **Qué es**: con `use_lockfile = true`, antes de cualquier operación Terraform hace un `PUT`
  condicional (`If-None-Match`) de un objeto `<key>.tflock` al lado del estado. Si el objeto ya
  existe, S3 rechaza la escritura y la segunda operación falla con `Error acquiring the state
  lock`. Al terminar, lo borra.

- **Por qué importa**: es lo que impide que dos `apply` simultáneos escriban el mismo objeto y
  corrompan el estado. Sin lock no hay ninguna protección — el último en escribir gana y el otro
  desaparece.

- **Lo que no se suele ver**: el lock deja rastro en el bucket y **se puede inspeccionar**. Con
  versioning activado quedan hasta los ciclos ya cerrados, como delete markers:

  ```json
  {"ID":"ea1f3de2-be0e-273c-e2a1-0ab301156572","Operation":"OperationTypePlan","Info":"",
   "Who":"lucca@LUQUITA","Version":"1.15.8","Created":"2026-08-18T12:26:13.211078748Z",
   "Path":"tf-state-workshop-lm-104981180500/tf-workshop/terraform.tfstate"}
  ```

  El campo `Who` es exactamente lo que aparece en el error del que se queda afuera, y `Operation`
  dice si el que tiene el lock está planificando o aplicando. Cuando un lock queda huérfano porque
  un `apply` murió a la mitad, **este objeto es el que hay que mirar antes de tocar
  `force-unlock`** — dice quién y desde cuándo.

- **Qué creía antes**: que el locking necesitaba DynamoDB porque S3 "no tiene transacciones". Lo
  que faltaba no eran transacciones sino **escrituras condicionales**, que S3 sumó y que alcanzan
  para un mutex. De ahí que `dynamodb_table` quedara deprecado en Terraform 1.11+.

- **Trampa práctica encontrada**: `--prefix tf-workshop/terraform.tfstate` en
  `list-object-versions` matchea **también** el `.tflock`. Al listar versiones de un estado hay que
  proyectar `Key`, o se terminan leyendo dos objetos distintos creyendo que son versiones de uno.

---

### `required_version` vs. `required_providers`: por qué el operador `~>` va en uno y no en otro

- **Qué es**: `~>` (pesimista) fija un techo implícito. `~> 1.10` significa `>= 1.10, < 2.0`
  (el último componente escrito puede incrementar); `~> 1.10.0` significa `>= 1.10.0, < 1.11.0`,
  mucho más estricto. `>= 1.10` es un piso mínimo puro, sin techo.

- **Por qué importa**: la diferencia no es de estilo, es **quién instala cada cosa**. El provider
  lo baja `terraform init` solo, sin aprobación de nadie: ahí querés un techo, porque un major
  nuevo del provider AWS puede cambiar el comportamiento de recursos existentes sin que hayas
  tocado una línea de HCL. El CLI de Terraform, en cambio, lo instala un humano a propósito.
  Poner `< 2.0` ahí es afirmar algo que no verificaste — que la config se rompe en Terraform 2.0.

- **Qué creía antes**: que `~>` era "la forma correcta" de escribir cualquier restricción de
  versión, por defecto. La restricción honesta es la que refleja el requisito real: acá el
  requisito es que `use_lockfile` necesita >= 1.10, y nada más. Quedó `required_version = ">= 1.10"`
  y `version = "~> 6.0"` en el provider.

---

### El `.terraform.lock.hcl` y para qué sirve de verdad

- **Qué es**: archivo que fija la versión exacta del provider resuelta en el primer `init`
  (acá `v6.60.0`, dentro del rango `~> 6.0`) junto con los hashes de sus binarios.

- **Por qué importa**: se vio en vivo durante el troubleshooting del timeout de registry. Cuando
  el `init` volvió a correr, el output fue `Reusing previous version of hashicorp/aws from the
  dependency lock file` / `Using previously-installed hashicorp/aws v6.60.0` — no volvió a
  descargar nada. Sin el lock, cada `init` en otra máquina puede resolver un provider distinto
  dentro del mismo `~> 6.0`.

- **Decisión asociada**: **se commitea**, contra lo que hace el enunciado del workshop (que lo
  pone en `.gitignore`). La fuente que zanjó la discusión es el propio Terraform, en el output
  del primer `init`: *"Include this file in your version control repository so that Terraform can
  guarantee to make the same selections by default"*. Cierra el riesgo abierto de `DISENO.md` §6.

- **Paralelismo real**: es un `package-lock.json`. Misma idea, mismo problema que resuelve.

---

### Una subnet no es pública por un flag: lo público se arma con tres piezas y una omisión

- **Qué es**: "subnet pública" no es un atributo de AWS. No existe ningún campo `public = true`.
  Es el resultado de tres recursos combinados: un **IGW** adjunto a la VPC, una **route table** con
  `0.0.0.0/0 → igw`, y una **association** que le pega esa tabla a la subnet.
  `map_public_ip_on_launch` no participa: solo hace que las instancias reciban IP pública, que sin
  ruta al IGW no sirve para nada.

- **Lo contraintuitivo**: **la subnet privada es privada por lo que falta, no por lo que se
  declaró.** No tiene ningún recurso propio que la haga privada. Al no asociarla a ninguna tabla,
  cae en la **main route table** de la VPC — que AWS crea sola, que este código no administra, y
  que solo tiene la ruta `local`. Sin `0.0.0.0/0`, no hay salida. Se puede adoptar esa tabla con
  `aws_default_route_table` si hiciera falta gobernarla; acá se deja en paz a propósito.

- **La otra ruta que no está escrita**: toda route table trae `10.0.0.0/16 → local` (el CIDR de la
  VPC) puesta por AWS, imposible de borrar y ausente del `plan`. Es la que hace que las dos subnets
  se hablen entre sí sin configurar nada. Cuando en la Fase 8 se compare el `plan` contra la
  consola, esa ruta va a estar en la consola y no en el código: no es drift.

- **Qué creía antes**: que `map_public_ip_on_launch = true` era lo que definía a la subnet como
  pública. Es al revés — es el único de los cuatro elementos que **no** aporta conectividad;
  aporta la dirección con la que la conectividad, si existe, se puede usar desde afuera.

---

### El security group niega por defecto, y Terraform es más estricto que la consola

- **Qué es**: un SG es un firewall **con estado** (la respuesta a una conexión permitida sale sola,
  sin regla de vuelta) y **solo permite**: no existen reglas de `deny`. Todo lo que no está
  explícitamente permitido, queda denegado.

- **Lo contraintuitivo, y es una trampa cara**: crear un SG por la API de AWS agrega solo una regla
  de egress **allow all**. Terraform la saca. Textual de la doc del provider:

  > "By default, AWS creates an `ALLOW ALL` egress rule when creating a new Security Group inside
  > of a VPC. When creating a new Security Group inside a VPC, Terraform will remove this default
  > rule, and require you specifically re-create it if you desire that rule."

  O sea que un `aws_security_group` sin egress declarado queda con **salida cero**, al revés de lo
  que pasa si lo creás por consola. El modo de falla es el peor de todos: la EC2 de la Fase 6
  arranca perfecto, el `user_data` no puede hacer `docker pull` ni `yum`, y desde afuera no hay
  ningún error que mire al SG. Mismo patrón que el riesgo del CRLF: el síntoma aparece a tres
  capas de la causa.

- **Por qué las reglas separadas se pueden taguear y las inline no**: cada
  `aws_vpc_security_group_ingress_rule` es un objeto real de AWS con su propio ID (`sgr-...`),
  visible en el `plan` como `security_group_rule_id`. Las reglas inline no eran objetos: vivían
  adentro del SG. Por eso ahora Terraform rastrea cada regla por separado, los diffs son
  quirúrgicos, y una regla agregada a mano por otro no se borra sola en el próximo `apply`.

- **Regla práctica**: una sola fuente por regla — `cidr_ipv4`, `cidr_ipv6`, `prefix_list_id` o
  `referenced_security_group_id`, exactamente uno. Dos orígenes son dos recursos. Y con
  `ip_protocol = "-1"` no van `from_port`/`to_port`: el concepto de puerto no aplica cuando el
  protocolo es "todos".

---

### El `id` del estado no siempre es un ID de AWS, y el `apply` no vuelve cuando la API dice "ok"

Dos cosas que se ven juntas en el registro DNS de la Fase 7 y que rompen dos suposiciones cómodas.

**Primera: el `id` de un recurso en el estado lo elige el provider, no AWS.** El del registro es
`Z0909248Q51XTVKXPOG_sf.luccamedina.ownboarding.teratest.net_A`, o sea zona + nombre + tipo pegados
con guiones bajos. No existe un "ID de registro" en Route53: la API direcciona los
`ResourceRecordSet` por esa terna, así que el provider la usa como identidad. Ya había aparecido el
mismo patrón en la Fase 5 con los `aws_iam_role_policy_attachment`
(`role-ec2-tf-workshop-lm/arn:aws:iam::aws:policy/...`), y por la misma razón: la relación
"política adjunta a rol" tampoco tiene identificador propio.

La consecuencia práctica aparece en la Fase 8: para importar uno de estos recursos hay que
**construir el `id` a mano con el formato exacto que espera el provider**, y ese formato está
documentado por recurso. No se lo saca de la consola de AWS, porque en la consola no existe.

**Segunda: `Creation complete after 35s` para un registro DNS.** Los recursos de red de la Fase 2
se crearon en menos de un segundo cada uno. Acá el provider no está esperando a la API —el
`ChangeResourceRecordSets` responde enseguida— sino a que el *change set* pase de `PENDING` a
`INSYNC`, que es Route53 confirmando que el cambio llegó a sus cuatro servidores autoritativos.

Es un ejemplo concreto de algo que aplica a todo Terraform: **un `apply` que termina no significa
"la API aceptó mi pedido", significa "el recurso alcanzó el estado que declaré"**. Los provider
esperan a la consistencia real cuando el servicio la expone. Y de paso explica por qué la
verificación con `dig` funcionó de una: cuando el `apply` volvió, la propagación autoritativa ya
había terminado. Lo único que podía faltar era cache del lado del cliente, no del lado de AWS.

---

## 7. Preguntas que me hice y su respuesta

Las del tipo "¿por qué no simplemente X?". Son las que después permiten defender las decisiones.

### ¿Por qué `vpc_id` va siempre en la primera línea del recurso? ¿El orden significa algo?

No, **HCL no le da ningún significado al orden de los argumentos**. Poner `tags` primero da un
resultado idéntico, y `terraform fmt` alinea los `=` pero **no reordena** nada.

Es convención, la del Registry: primero lo que dice **dónde vive** el recurso (`vpc_id`,
`security_group_id`), después la configuración (`cidr_block`, `availability_zone`), después los
flags (`map_public_ip_on_launch`), después los bloques anidados (`route {}`), y `tags` siempre al
final. La utilidad concreta: leyendo la primera línea de cualquier recurso sabés en qué VPC estás
parado sin leer el resto.

El caso que confirma la lógica es `aws_route_table_association`, que **no** tiene `vpc_id`: no
cuelga de la VPC, cuelga de una subnet y de una tabla, y sus dos primeras líneas son exactamente
esas.

---

## 8. Capturas pendientes

Formato exacto que espera la skill de documentación.

- `CAPTURA PENDIENTE -- [pantalla, vista/filtro, y qué se tiene que ver]`

---

## 9. Notas sueltas

Cualquier cosa que no entre en las categorías de arriba pero que valga la pena no perder.

### El riesgo de CRLF, desarmado antes de la Fase 6 (con el comando que lo demuestra)

El entorno estaba efectivamente armado para repetir el problema del lab anterior:

```bash
git config --get core.autocrlf   # -> true
ls .gitattributes                # -> no existe
```

```
warning: in the working copy of '.terraform.lock.hcl', LF will be replaced by CRLF
```

**Por qué importa en Fase 6, en concreto**: `scripts/user-data.sh.tftpl` pasa por
`templatefile()` tal cual está en disco y se inyecta en el `user_data` de la EC2. Si tiene
retorno de carro, `cloud-init` intenta ejecutar `/bin/bash` con un `\r` pegado, no encuentra ese
binario, y **el script falla sin error visible**: la instancia arranca perfecto, `docker ps` no
muestra nada, y no hay ninguna pista en la consola de EC2. El síntoma aparece a tres capas de
distancia de la causa.

**El comando que hay que conocer** — muestra el line ending en el índice (`i/`) y en el working
tree (`w/`) por separado, que es lo que ningún otro chequeo distingue:

```bash
git ls-files --eol -- '*.tf'
```

### La AMI del data source ya se movió, y el `plan` de la Fase 7 no lo mostró de casualidad

En la Fase 1 el data source resolvió `ami-07a5b367e8dc8bd92`
(`al2023-ami-2023.12.20260803.3-kernel-6.1-x86_64`). En el `apply` de la Fase 7 resolvió
`ami-02b3d83d84b07786d` (`al2023-ami-2023.12.20260817.0-kernel-6.1-x86_64`): AWS publicó un build
nuevo de la misma línea entre una fase y la otra, y `most_recent = true` lo siguió sin que nadie
tocara una línea de código.

El `plan` dijo `0 to change, 0 to destroy` **solo porque la instancia se creó en la Fase 6, ya con
el build del 17-ago**. Verificado contra el estado:

```bash
terraform state show aws_instance.game | grep -E "^\s+(ami|instance_state|public_ip)\s+="
    ami                                  = "ami-02b3d83d84b07786d"
    instance_state                       = "running"
    public_ip                            = "3.234.229.254"
```

O sea: el valor que quedó registrado en `CLAUDE.md` y en la tabla de trazabilidad como "la AMI de la
Fase 1" ya no es el que está corriendo. Coincidieron de suerte, no por diseño.

**Lo que esto anticipa de la Fase 8.** El argumento `ami` de `aws_instance` fuerza reemplazo. El día
que AWS publique el próximo build de la línea `kernel-6.1`, un `terraform plan` sin ningún cambio en
el repo va a proponer **destruir y recrear la instancia** — y con `user_data_replace_on_change = true`
ya en juego, eso arrastra IP pública nueva y por lo tanto el registro DNS de la Fase 7 actualizándose
también. Es "drift" en el sentido inverso al que uno espera: no cambió la infraestructura, cambió
**lo que el código significa**.

Es el mismo problema que `FROM nginx:alpine` sin digest, ya anotado en la tabla de lab vs.
producción. La mitigación en producción es idéntica en los dos casos: pinear el valor exacto y
actualizarlo por decisión, no por calendario de AWS.

### El distro por defecto de WSL en esta máquina no es Ubuntu

En la segunda máquina, `wsl -e bash` falla:

```
<3>WSL (840 - Relay) ERROR: CreateProcessCommon:798: execvpe(bash) failed: No such file or directory
```

La causa se ve en el listado:

```bash
wsl -l -v
  NAME              STATE     VERSION
* docker-desktop    Running   2
  Ubuntu            Running   2
```

Docker Desktop instala su propio distro y **se quedó con el asterisco de default**. Ese distro es una
imagen mínima que no trae `bash`, así que cualquier comando lanzado sin especificar distro muere con
un error que parece de PATH y es de distro equivocado. Todo lo que corra Terraform tiene que ir con
`wsl -d Ubuntu -e bash -lc '...'`.

---

## 10. Estado al momento de generar la documentación — qué falta y dónde van los placeholders

**Leer esto antes de armar el documento final.** Este repo se congela acá para una primera pasada de
documentación, con las **Fases 0 a 7 cerradas y verificadas** y las **Fases 8 y 9 sin ejecutar**.

El documento tiene que salir completo en todo lo que sí se hizo, y **dejar secciones vacías con
placeholders visibles** para lo que falta — no omitirlas ni inventarlas. La idea es que después se
rellenen sin rehacer el documento.

### Lo que está cerrado y va completo

| Fase | Contenido disponible en esta bitácora |
|---|---|
| 0 — Bootstrap | §2 (4 bloques de verificación), §3 (3 problemas reales), §4, §9 |
| 1 — Data sources | §2 (2 bloques), §4 (3 decisiones), §6 (`most_recent`) |
| 2 — Red | §2 (`plan` + `apply` verificado contra la API), §3 (`cannot begin with sg-`), §4, §5, §6, §7 |
| 3 — Backend S3 | §2 (migración completa), §3 (state lock huérfano), §4, §6 (estado, `lineage`/`serial`, el lock como objeto) |
| 4 — ECR + imagen | §2, §3 (socket de Docker), §4 (6 decisiones), §5 |
| 5 — IAM | §2, §4, §5 |
| 6 — EC2 + user_data | §2 (del `.tftpl` al HTTP 200), §4 (6 decisiones), §5, §9 (CRLF) |
| 7 — DNS | §2, §4 (5 decisiones), §5, §6 (`id` compuesto e `INSYNC`), §9 (drift de la AMI) |

### Lo que falta — dejar placeholder explícito

**Fase 8 — Drift e import. NO EJECUTADA.** El documento tiene que llevar su capítulo con la
estructura armada y el contenido pendiente. Los tres ejercicios previstos:

1. **Drift provocado a mano.** Cambiar algo por consola (candidato: la descripción de una regla del
   SG, o un tag de la instancia), y detectarlo con `terraform plan -refresh-only`. Falta: el comando,
   su output literal, y la explicación de por qué `-refresh-only` no es lo mismo que un `plan` común.
2. **Import de un recurso creado fuera de Terraform.** Falta: qué recurso, el `id` con el formato
   exacto que espera el provider, el bloque `import {}` o el `terraform import`, y el `plan` posterior
   demostrando **cero diff** — que es el único criterio de que el import salió bien.
3. **Drift "al revés" de la AMI** (ver §9). No hay que provocarlo: ya está latente. Falta: el `plan`
   del día en que AWS publique el próximo build de `al2023-ami-2023.*-kernel-6.1-x86_64`, mostrando
   el reemplazo de la instancia sin ningún cambio en el repo.

```
PLACEHOLDER -- Fase 8, ejercicio 1: output literal de terraform plan -refresh-only con el drift
detectado, y captura de la consola de AWS mostrando el cambio manual antes de correrlo
```

```
PLACEHOLDER -- Fase 8, ejercicio 2: comando de import, id compuesto usado, y el plan posterior
diciendo "No changes"
```

```
PLACEHOLDER -- Fase 8, ejercicio 3: plan que propone reemplazo de la instancia por AMI nueva,
con los dos IDs de AMI visibles en el diff
```

**Fase 9 — Cierre y `destroy`. NO EJECUTADA.** Falta: el output del `terraform destroy`, el conteo de
recursos destruidos, la verificación por CLI de que la cuenta quedó en cero, y el borrado **manual**
del bucket de estado `tf-state-workshop-lm-104981180500`, que el `destroy` no toca porque se creó
fuera de Terraform (§1).

```
PLACEHOLDER -- Fase 9: output de terraform destroy con el conteo final, verificacion por CLI de
cuenta en cero, y borrado manual del bucket de estado
```

**Capturas pendientes.** Las anotadas a lo largo de §2 no están tomadas todavía. Van al documento
como huecos con su leyenda, no eliminadas.

### Advertencia sobre la infraestructura viva

Al momento de esta pasada **la infraestructura está corriendo**: la EC2 `i-038459aacc0d1e104` factura
mientras exista, y el juego responde en `http://sf.luccamedina.ownboarding.teratest.net`. Las Fases 8
y 9 dependen de que siga viva. Si se destruye antes de ejecutarlas, hay que reconstruirla con
`terraform apply` — el código está completo y el estado en S3, así que es reproducible, pero los IDs
de la tabla de trazabilidad de §1 **cambian todos** salvo los del bucket y el repositorio ECR.

Antes de la mitigación:

```
i/lf    w/crlf    attr/text eol=lf    providers.tf
i/lf    w/crlf    attr/text eol=lf    variables.tf
i/lf    w/crlf    attr/text eol=lf    versions.tf
```

Después:

```
i/lf    w/lf      attr/text eol=lf    providers.tf
i/lf    w/lf      attr/text eol=lf    variables.tf
i/lf    w/lf      attr/text eol=lf    versions.tf
```

**Lo importante de esa tabla**: el índice ya estaba en LF con solo `.gitattributes` — la
normalización de Git funcionaba. Lo que seguía en CRLF era **el archivo del disco**, escrito por
el editor. Y el disco es exactamente lo que lee `templatefile()`. Por eso hacen falta las dos
piezas y no alcanza con la de Git, que fue la conclusión apurada inicial.

Para renormalizar archivos que ya están en el working tree con el final de línea equivocado, no
alcanza con `git checkout` — Git los considera sin cambios porque tras normalizar son idénticos.
Hay que forzarlo borrando y recuperando:

```bash
rm providers.tf variables.tf versions.tf && git checkout -- providers.tf variables.tf versions.tf
```

**Chequeo obligatorio antes del `apply` de la Fase 6**: `file scripts/user-data.sh.tftpl` no
tiene que decir `with CRLF line terminators`.
