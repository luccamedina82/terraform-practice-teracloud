# Terraform Practice - Teracloud

Repo de práctica para aprender Terraform, recurso por recurso, antes de pasar a módulos completos.

## Estructura actual del repo

```
.
├── provider.tf          # Provider AWS (root) + backend remoto en S3
├── vpc.tf                # Recurso: VPC
├── backend/              # Bootstrap: crea el bucket S3 que guarda los estados
│   ├── provider.tf       # Provider AWS (usa estado LOCAL a propósito)
│   └── s3.tf              # Bucket S3 + versionado
└── .gitignore
```

- El estado del `backend/` (el que crea el bucket) queda **local** a propósito: es el bootstrap, no puede depender de sí mismo.
- El resto de los recursos (VPC, etc.) guardan su estado en S3 (`teracloud-terraform-state`), con versionado y locking nativo (`use_lockfile`).

---

## Buenas prácticas de Terraform

### 1. Estado (state)
- **Nunca** el estado en local para trabajo en equipo ni en producción — usar backend remoto (S3, Azure Storage, GCS, Terraform Cloud).
- Habilitar **versionado** en el bucket de estado: permite recuperar una versión anterior si un `apply` rompe algo.
- Habilitar **locking** (nativo de S3 con `use_lockfile`, o DynamoDB en setups más viejos) para que dos personas no corran `apply` al mismo tiempo y corrompan el estado.
- Encriptar el bucket de estado (SSE-S3 o KMS) y bloquear acceso público — el `.tfstate` puede contener secretos en texto plano (passwords, keys, etc. que terminan como atributos de recursos).
- Un `key` (ruta) distinto por stack/módulo dentro del mismo bucket, ej: `vpc/terraform.tfstate`, `s3/terraform.tfstate`.
- Nunca commitear `*.tfstate` ni `*.tfstate.backup` a git.

### 2. Secretos y credenciales
- Nunca hardcodear `access_key`/`secret_key` en `.tf` ni `.tfvars`.
- Usar el proveedor de credenciales por defecto: profiles de AWS CLI (`~/.aws/credentials`), variables de entorno, o roles IAM (en CI/CD, OIDC en vez de keys estáticas).
- Si algo se filtra (aunque sea por un momento, en un chat o commit), rotarlo inmediatamente.

### 3. Código
- `terraform fmt` antes de cada commit (formato consistente).
- `terraform validate` y `terraform plan` antes de cualquier `apply`.
- Fijar versiones de provider (`~> 6.0`) y de Terraform (`required_version`) para evitar romper el código con upgrades inesperados.
- Commitear siempre `.terraform.lock.hcl` (fija las versiones exactas resueltas de providers).
- Nombres de recursos descriptivos y consistentes (`aws_vpc.main`, no `aws_vpc.vpc1`).
- Tagear todos los recursos (`Environment`, `Project`, `Owner`, `ManagedBy = "terraform"`) — ayuda a auditar costos y a distinguir qué está manejado por Terraform.
- Evitar lógica compleja en `.tf`; si hace falta, mejor un módulo bien documentado que un archivo gigante con condicionales.

### 4. Flujo de trabajo
- Cambios de infraestructura vía Pull Request, igual que código de aplicación — alguien más revisa el `plan` antes de aplicar.
- Idealmente, `plan` corre automático en CI en cada PR, y el `apply` es manual o gated (aprobación).
- Empezar recurso por recurso (como venimos haciendo) antes de armar módulos — así entendés qué hace cada bloque antes de abstraerlo.
- Cuando algo se repite entre 2-3 lugares (mismo bucket con distinta config, misma VPC en distintos ambientes), ahí sí conviene un módulo.

### 5. Seguridad
- Principio de mínimo privilegio: el usuario/rol que corre Terraform solo debería tener permisos sobre lo que ese stack gestiona.
- Revisar el `plan` buscando "destroy" inesperados antes de aplicar, sobre todo en producción.
- `prevent_destroy` en el lifecycle de recursos críticos (el bucket de estado, bases de datos, etc.).

---

## Estructuras de carpetas típicas

No hay una única forma "correcta" — depende del tamaño del equipo y de cuánto varía la infra entre ambientes. Algunas convenciones comunes:

### A) Por ambiente (la más común para empezar)

Cada ambiente es un stack independiente, con su propio state y su propio `.tfvars`. Comparten módulos.

```
infra/
├── modules/
│   ├── vpc/
│   ├── s3/
│   └── ec2/
├── environments/
│   ├── dev/
│   │   ├── main.tf          # llama a los módulos
│   │   ├── backend.tf       # key = "dev/terraform.tfstate"
│   │   └── terraform.tfvars
│   ├── staging/
│   │   ├── main.tf
│   │   ├── backend.tf       # key = "staging/terraform.tfstate"
│   │   └── terraform.tfvars
│   └── production/
│       ├── main.tf
│       ├── backend.tf       # key = "production/terraform.tfstate"
│       └── terraform.tfvars
```

Ventaja: aislamiento total entre ambientes (un error en dev no puede tocar prod, ni siquiera el state). Es el patrón que recomienda HashiCorp para la mayoría de los casos, en vez de Terraform Workspaces (los workspaces comparten backend/config y es más fácil aplicar donde no correspondía).

### B) Por región / zona de disponibilidad

Cuando la infra se replica en múltiples regiones (multi-region activo-activo, o simplemente recursos regionales separados):

```
environments/
└── production/
    ├── us-east-1/
    │   ├── main.tf
    │   └── backend.tf        # key = "production/us-east-1/terraform.tfstate"
    └── eu-west-1/
        ├── main.tf
        └── backend.tf        # key = "production/eu-west-1/terraform.tfstate"
```

Cada región tiene su propio state — permite aplicar cambios en una región sin arriesgar la otra, y en un evento regional (outage) el state de la otra región sigue intacto y operable.

### C) Combinado: ambiente + región

```
environments/
├── dev/
│   └── us-east-1/
├── staging/
│   └── us-east-1/
└── production/
    ├── us-east-1/            # primaria
    └── us-west-2/            # secundaria / DR
```

### D) Disaster Recovery (DR)

Patrón activo-pasivo típico: la región primaria tiene toda la infra activa, la región DR tiene una copia (a veces con `count`/`var.is_dr_region` para escalar en frío) lista para promoverse. Claves:

- **State separado por región** — nunca un solo state para primaria + DR (si se corrompe el state, no querés perder también la referencia a la infra de respaldo).
- Backend del state de DR también replicado o en una cuenta/región distinta a la primaria (si S3 primaria no está disponible, necesitás poder seguir gestionando DR).
- Variables por región para lo que cambia (AMIs, CIDR, tamaños) mientras el módulo es el mismo — así primaria y DR no divergen en la definición, solo en los parámetros.

```
environments/production/
├── primary-us-east-1/
│   ├── main.tf              # usa module "app" con vars de la región
│   ├── backend.tf           # key = "production/primary/terraform.tfstate"
│   └── terraform.tfvars     # region = us-east-1, instance_count = 3
└── dr-us-west-2/
    ├── main.tf              # mismo module "app"
    ├── backend.tf           # key = "production/dr/terraform.tfstate"
    └── terraform.tfvars     # region = us-west-2, instance_count = 1 (standby)
```

### Regla general

Cuantos más ambientes/regiones, más vale la pena separar en `modules/` (la definición, reutilizable) vs. `environments/` (los parámetros por stack). Nuestro repo hoy es simple (raíz = VPC, `backend/` = bootstrap del state) porque estamos en la etapa de "un recurso a la vez" — cuando pasemos a manejar más de un ambiente, ahí migramos a alguna de estas estructuras.
