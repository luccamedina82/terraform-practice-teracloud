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
| Bucket S3 de estado (Fase 0, **fuera de Terraform**, creado por CLI) | `tf-state-workshop-lm-104981180500` | `arn:aws:s3:::tf-state-workshop-lm-104981180500` | `us-east-1` · versioning `Enabled` · SSE-S3 (`AES256`) con `BucketKeyEnabled` · block public access en los 4 flags · tags `Project`/`ManagedBy`/`Purpose` | Sí, pero despreciable: el bucket en sí no cuesta, solo el almacenamiento del `.tfstate` (unos KB) y sus versiones. Del orden de centavos de USD al mes. **No lo borra `terraform destroy`** — hay que eliminarlo a mano en Fase 9 |

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

## 4. Decisiones tomadas durante la ejecución

Las que no estaban en `DISENO.md` o que lo contradicen. Incluir explícitamente las que
cambiaron de opinión a mitad de camino.

| Fase | Decisión | Alternativa descartada | Por qué | ¿Contradice el diseño original? |
|---|---|---|---|---|
| 0 | Trabajar 100% en WSL Ubuntu 26.04, instalando Terraform ahí | Trabajar 100% en Windows instalando el AWS CLI ahí (Terraform ya estaba en Windows v1.15.8) | El entorno estaba partido: Terraform solo en Windows, AWS CLI solo en WSL. Unificar en WSL mantiene una sola shell para `plan` + verificación por CLI, respeta el entorno que ya venía usando, y evita el riesgo de CRLF del `user-data.sh.tftpl` que ya había mordido en un lab anterior | No — `DISENO.md` §1 ya asumía WSL; el diseño no había registrado que Terraform no estaba instalado ahí |
| 0 | `backend "local" {}` declarado explícitamente en vez de omitir el bloque | Dejar el backend local implícito (comportamiento idéntico) | Funcionalmente son equivalentes, pero el explícito hace que la migración de Fase 3 sea un diff de una línea (`"local"` → `"s3"`) en vez de la aparición de un bloque de la nada. Además Terraform recién entonces escribe `.terraform/terraform.tfstate` con el `hash` del backend, que es contra lo que compara para detectar el cambio y ofrecer migrar el estado | No — el diseño pedía backend local en Fase 0-2, no decía cómo expresarlo |
| 0 | `.terraform.lock.hcl` **se commitea** | Ignorarlo, como hace el enunciado del workshop | Lo zanjó el output del propio `terraform init`: *"Include this file in your version control repository so that Terraform can guarantee to make the same selections by default"*. Sin él, otro `init` puede resolver un provider distinto dentro de `~> 6.0` | Sí, contradice el enunciado — divergencia deliberada y documentada. Cierra el riesgo de `DISENO.md` §6 |
| 0 | `required_version = ">= 1.10"` (piso mínimo) en vez de `~> 1.10` | Restricción pesimista con techo en 2.0 | El requisito real es solo que `use_lockfile` necesita >= 1.10. Poner `< 2.0` afirmaría algo no verificado. El `~>` sí se mantiene en el provider (`~> 6.0`), porque ese lo instala `init` solo y sin aprobación humana | No |
| 0 | `region` y `default_tags` salieron a `variables.tf` ya en Fase 0 | Hardcodearlas en `providers.tf` y refactorizar después | Sale gratis hacerlo bien de entrada y evita un refactor posterior | No — `DISENO.md` §2 ya preveía `variables.tf`, solo que no en esta fase |
| 0 | Terraform instalado como binario en `~/.local/bin`, no por `apt` | Repo de HashiCorp vía `apt` (el método oficial recomendado) | El `apt` exige `sudo` y todo lo que se lanza desde Claude Code va sin TTY, así que la password no se puede tipear. El binario no necesita root y conserva la misma garantía verificando firma GPG + SHA256 a mano. Contra: las actualizaciones son manuales — irrelevante acá porque `required_version` en `versions.tf` pinea la versión igual | No — el diseño no fijaba método de instalación |
| 0 | Repo en `/mnt/c/Users/lucca/desktop/teracloud/terraform`, no en el home de WSL | Mover el repo a `~/` dentro de WSL (mejor performance de I/O) | Los archivos se editan desde Windows y se ejecuta desde WSL sobre el mismo path montado; mover el repo partiría el trabajo entre dos filesystems. El volumen de este lab no justifica el overhead de `/mnt/c` | No — el diseño no se pronunciaba |
| 0 | Commitear el borrado de los archivos del lab anterior en `main` | Reinicializar el repo desde cero descartando el historial | El historial deja registro de que la infra anterior existió y se eliminó a propósito; reinicializar lo perdía. Commit `4cb46a0`, 8 archivos, 273 líneas eliminadas | No |

---

## 5. Lab vs. producción

Cada vez que algo se hace "porque es un lab", va acá. Base inicial en `DISENO.md` sección 8.

| Decisión (lab) | Por qué | En producción |
|---|---|---|
| Usuario IAM personal con `AdministratorAccess` y access keys estáticas de larga vida | Lo pide el enunciado del workshop. Verificado en Fase 0: política adjunta directa, sin permissions boundary y sin SCPs (cuenta standalone) — o sea, permiso total y sin ningún techo | OIDC federation desde el CI/CD hacia un rol con permisos mínimos por servicio; cero credenciales estáticas. Contradice de frente el criterio de OIDC del Workshop 5 |
| Cuenta AWS fuera de una organización, sin SCPs | Cuenta de lab individual | Cuenta miembro de una organización con SCPs como red de contención: restricción de regiones habilitadas, prohibición de borrar CloudTrail/logs, y bloqueo de acciones IAM privilegiadas fuera del pipeline |
| Las mismas access keys replicadas en `~/.aws` de WSL y de Windows (3 perfiles, misma key `...PD7H`) | Comodidad de tener las credenciales disponibles desde cualquiera de las dos shells | Credenciales de corta duración vía SSO / `assume-role`, nunca material estático duplicado en varios filesystems. Cada copia es una superficie más de la que se puede filtrar |

---

## 6. Conceptos nuevos de Terraform

Explicados en criollo, como se los contaría a alguien. Prioridad a lo contraintuitivo.

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

## 7. Preguntas que me hice y su respuesta

Las del tipo "¿por qué no simplemente X?". Son las que después permiten defender las decisiones.

### ¿...?

---

## 8. Capturas pendientes

Formato exacto que espera la skill de documentación.

- `CAPTURA PENDIENTE -- [pantalla, vista/filtro, y qué se tiene que ver]`

---

## 9. Notas sueltas

Cualquier cosa que no entre en las categorías de arriba pero que valga la pena no perder.
