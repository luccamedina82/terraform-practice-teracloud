# CLAUDE.md — Workshop Terraform en AWS

Contexto permanente para las sesiones de Claude Code en este repo.
Leer también `DISENO.md` (diseño en papel) y `BITACORA.md` (registro vivo) al arrancar.

---

## Quién soy

Lucca Medina, estudiante de 4º de Ingeniería en Sistemas (UTN FRC Córdoba), pasante de
Cloud Engineering en Teracloud (AWS Partner). Idioma de trabajo: **español**.

Experiencia previa relevante (todo hecho a mano por consola, sin IaC): EC2/ALB/ASG/CloudFront,
VPC peering y subnetting, ECS en modo EC2 con ECR y Cloud Map, EFS, CodePipeline/CodeBuild/
CodeDeploy, GitHub Actions con OIDC. **Terraform es la brecha que estoy cerrando con este
workshop** — la infraestructura de este lab es más simple que lo que ya construí; lo nuevo
es la herramienta, no AWS.

---

## Cómo trabajo (importante)

- **Guía, no solución.** Quiero entender cada campo antes de escribirlo.
- **Modalidad vigente desde el 14-ago-2026 — "vos escribís, yo aprendo mirando":** escribí vos el
  HCL, **de a un paso por vez**, y explicá cada campo *antes* de pegarlo. Un paso = un recurso o un
  grupo chico de recursos que solo tienen sentido juntos (ej.: IGW + route table + association).
  Después de cada paso: `terraform fmt` + `validate`, y frenar a esperar mi OK antes del siguiente.
  Esto **reemplaza** la modalidad anterior ("escribo yo el HCL, vos revisás"), que se usó hasta la
  Fase 2 inclusive. El objetivo no cambió: entender cada campo. Cambió quién teclea.
- Lo que se explica de cada campo: qué hace, qué pasa si falta, y en qué fase posterior muerde.
  Las trampas y los defaults implícitos valen más que la descripción del argumento.
- **En diseño**: preguntas socráticas bienvenidas. **En ejecución/troubleshooting**: respuestas
  directas con la razón incluida, sin una pregunta por cada paso.
- **Causa raíz antes que workaround.** Si algo falla, quiero saber por qué falló, no solo cómo
  hacerlo andar.
- **Fuente primaria.** Ante una duda de comportamiento o de precio: doc oficial de AWS/HashiCorp,
  Terraform Registry, o el API. No blogs ni resúmenes.
- **Validación incremental.** Nunca construir todo y probar al final. Cada fase se valida antes
  de sumar la siguiente.
- **Preguntá antes de asumir.** Si falta un dato (nombre, puerto, elección de imagen), preguntá.

## Anti-patrones — no hacer

- No correr `terraform apply` ni `terraform destroy` sin que lo pida explícitamente.
- No commitear ni pushear sin pedirlo.
- No escribir credenciales, account IDs ni secretos en archivos versionados.
- No inventar nombres de argumentos de recursos: verificar contra el Terraform Registry.
- No saltar fases del plan de `DISENO.md`.

---

## Parámetros del proyecto

| Parámetro | Valor |
|---|---|
| Cuenta AWS | `104981180500` |
| Región | `us-east-1` (el enunciado dice `us-east-2`; desviación deliberada) |
| Dominio | `luccamedina.ownboarding.teratest.net` (hosted zone ya existente en la cuenta) |
| Convención de nombres | sufijo `-lm`, vía `local.name_suffix` |
| Cuenta | Limpia — no hay infra de labs anteriores corriendo |
| Backend | S3 con `use_lockfile = true` (requiere Terraform >= 1.10), sin DynamoDB |
| Bucket de estado | `tf-state-workshop-lm-104981180500` (creado por CLI en Fase 0) |
| Key del estado | `tf-workshop/terraform.tfstate` — **no cambiar**: cambiarla equivale a perder el estado |
| Perfil AWS | `default` |
| Entorno local | WSL Ubuntu 26.04. Terraform v1.15.8 en `~/.local/bin` (binario, no `apt`) |
| Repo | `/mnt/c/Users/lucca/desktop/teracloud/terraform-practice-teracloud` — se edita desde Windows, se ejecuta desde WSL |

**Ojo con Windows/WSL**: ya me mordió el CRLF en un lab anterior (shebangs corruptos sin error
visible). Cualquier `.sh` que se escriba acá tiene que quedar en LF.

---

## Decisiones ya cerradas (no reabrir sin motivo)

1. Archivos `.tf` separados por dominio, no un `main.tf` monolítico.
2. `default_tags` en el bloque `provider`.
3. Nombres construidos desde un `local`, nunca hardcodeados por recurso.
4. Reglas de SG como recursos separados (`aws_vpc_security_group_ingress_rule`), no bloques inline.
5. `user_data` vía `templatefile()` a `scripts/user-data.sh.tftpl`.
6. Backend local en las primeras fases, migración a S3 en la Fase 3 (a propósito).
7. Bucket de estado creado por CLI, fuera de Terraform.

---

## Registro para la documentación final (crítico)

Al terminar el workshop, todo esto se lleva de vuelta al chat web para generar la documentación
con la skill `documentacion-tecnica` (Word, estilo propio). **Si no queda escrito en
`BITACORA.md` durante el trabajo, se pierde.**

Después de cada hito, actualizar `BITACORA.md` con lo que corresponda:

- **Troubleshooting**: síntoma observado (literal, con el error real) → hipótesis descartadas →
  causa raíz → fix aplicado → lección. Los problemas reales, no hipotéticos.
- **Decisiones**: qué se decidió, qué alternativa se descartó, y por qué. Incluidas las que se
  toman a mitad de camino y contradicen el diseño original — esas son las más valiosas.
- **Lab vs. producción**: cada vez que se hace algo "porque es un lab", va como fila de la tabla.
- **Conceptos nuevos**: lo que se entendió de Terraform que no se sabía antes, explicado en
  criollo. Sobre todo lo contraintuitivo.
- **Comandos y outputs**: los comandos de verificación con su salida real (pegada, no descrita).
- **IDs reales de recursos**: para la tabla de trazabilidad del doc.
- **Capturas pendientes**: cuando algo se ve mejor en una captura, anotar
  `CAPTURA PENDIENTE -- [qué pantalla y qué se tiene que ver]`.

Regla práctica: **si algo llevó más de diez minutos de resolver, va a la bitácora**, aunque en
retrospectiva parezca obvio.

---

## Estado de avance

Actualizar al cerrar cada fase.

| Fase | Estado |
|---|---|
| 0 — Bootstrap (perfil, bucket, repo, provider) | **cerrada** — `init` OK · `plan` "no changes" · `sts` OK · bucket creado y endurecido |
| 1 — Data sources | **cerrada** — `apply` con `0 added` · zone `Z0909248Q51XTVKXPOG` · AMI `ami-07a5b367e8dc8bd92` |
| 2 — Red | **cerrada** (18-ago-2026) — `apply` OK, 10 recursos managed · verificado por CLI contra la API · VPC `vpc-09b6544aea696e9dd` · SG `sg-0b1c39e081bc25b04` |
| 3 — Migración a backend S3 | **cerrada** (18-ago-2026) — `init -migrate-state` OK · objeto en S3 cifrado y versionado · 10 managed + 2 data preservados · `plan` = `No changes` |
| 4 — ECR + push de la imagen | **cerrada** (18-ago-2026) — repo `sf-tf-workshop-lm` · imagen propia sobre `nginx:alpine` · `list-images` devuelve `latest` · scan on push con **0 hallazgos** |
| 5 — IAM | **cerrada** (18-ago-2026) — rol `role-ec2-tf-workshop-lm` · 2 políticas adjuntas · instance profile `AIPARQ4K5WBKHX6MIHWCV` contiene el rol, verificado por CLI |
| 6 — EC2 + user_data | pendiente |
| 7 — DNS | pendiente |
| 8 — Drift e import | pendiente |
| 9 — Cierre y destroy | pendiente |

**Decisiones abiertas**: ninguna.

**Cerradas en Fase 4** — el juego y su puerto, que era la única decisión abierta del proyecto:

| Parámetro | Valor |
|---|---|
| Juego | Street Fighter II, demo en CSS de `jkneb` (fuente: `github.com/jkneb/street-fighter-css`) |
| Imagen | Construida por nosotros: `FROM nginx:alpine` + `COPY . /usr/share/nginx/html` + `.dockerignore` |
| Puerto del contenedor | **80** (nginx). El `user_data` de la Fase 6 va con `docker run -d -p 80:80` |
| `var.game_name` | `sf` — alimenta el nombre del repo ECR y el subdominio |
| URL final | `http://sf.luccamedina.ownboarding.teratest.net` |
| Digest en ECR | `sha256:9dd22a3cef18c5c93eb17d79d4a008d748ea32396f96625d1729421f44b8e6e9` |

Como el contenedor escucha en 80 y se mapea `-p 80:80`, **la regla de ingress 8080 del SG queda sin
uso**. Ya está anotada como fila de lab vs. producción; no se toca para no reabrir la Fase 2.

**Cerradas en Fase 0**: bucket de estado `tf-state-workshop-lm-104981180500` · perfil AWS
`default` · Terraform por binario en `~/.local/bin` en vez de `apt` (ver bitácora §3).

**Ojo — todo lo que pida `sudo` o input interactivo lo tenés que correr vos en una terminal
real**: lo que lanzo yo va sin TTY y se cuelga sin devolver error. Aplica también a
`terraform apply` sin `-auto-approve`, que pide el `yes` por el mismo canal.

---

## Trabajo en dos máquinas (desde 14-ago-2026)

El repo se sincroniza por GitHub (`luccamedina82/terraform-practice-teracloud`), pero
**`terraform.tfstate` NO viaja por git** — está en `.gitignore` porque guarda secretos en texto
plano. Mientras el backend siga siendo `local`, cada máquina tiene su propio estado.

**Regla mientras el backend sea local: aplicar desde UNA SOLA máquina.** Si se corre `apply` en
la PC A y después en la PC B, la B no sabe que los recursos existen y los crea de nuevo —
quedan VPCs duplicadas y recursos huérfanos que ningún `destroy` limpia.

Al momento del traspaso el estado tenía **cero recursos managed** (solo los dos data sources),
así que no había nada que perder. Si eso deja de ser cierto, adelantar la **Fase 3** (migración
del backend a S3) resuelve el problema de raíz: el estado pasa a estar compartido y con lock.

Requisitos para levantar el trabajo en una máquina nueva: Terraform >= 1.10, credenciales de la
cuenta `104981180500` en `~/.aws`, y `terraform init` (baja el provider **para esa plataforma** —
el `.terraform.lock.hcl` hoy solo tiene el hash `h1:` de `linux_amd64`).

### Segundo traspaso — 14-ago-2026, al terminar de escribir la Fase 2

Verificado antes de mover: **la cuenta sigue en cero recursos managed**. `aws ec2 describe-vpcs
--region us-east-1` devuelve únicamente la VPC default (`vpc-08bacc1ca6a59f5dc`, `172.31.0.0/16`),
y no existe `terraform.tfstate` en ninguna de las dos máquinas — el `apply` de la Fase 2 **no se
corrió**. O sea que el traspaso vuelve a ser gratis y la regla de "aplicar desde una sola máquina"
sigue sin haberse puesto a prueba.

**Lo primero al retomar en la máquina nueva**, en este orden:

1. `git pull`
2. `terraform init` (el `.terraform/` no viaja: es caché de binarios por plataforma)
3. `terraform plan` → tiene que decir `10 to add, 0 to change, 0 to destroy`
4. Recién ahí `terraform apply`, y **desde esa máquina en adelante, siempre la misma** hasta
   completar la Fase 3.

Si el `plan` dijera otra cosa que `10 to add`, parar: significa que alguien aplicó desde otro lado
y hay que reconciliar antes de tocar nada.

### 18-ago-2026 — la regla se activó y se desactivó el mismo día

Por la mañana el `apply` de la Fase 2 **se corrió** desde la máquina con WSL, y el estado con los
10 recursos managed quedó viviendo solo en ese disco. Ahí la regla de "una sola máquina" pasó de
teórica a activa, y la Fase 3 dejó de ser el siguiente paso del plan para ser la mitigación de un
riesgo real.

Se hizo la Fase 3 a continuación. **El estado está ahora en
`s3://tf-state-workshop-lm-104981180500/tf-workshop/terraform.tfstate`, cifrado, versionado y con
lock nativo de S3.**

**Consecuencia: la regla de "aplicar desde una sola máquina" queda LEVANTADA.** Ya se puede
trabajar desde cualquiera de las dos:

- Las dos leen y escriben el **mismo** estado, así que ninguna puede recrear lo que la otra creó.
- `use_lockfile = true` impide que dos operaciones simultáneas se pisen: la segunda corta con
  `Error acquiring the state lock` en vez de corromper el estado.
- El versioning del bucket deja restaurable cada escritura anterior.

Lo único que sigue sin viajar por git es `.terraform/` (caché de binarios por plataforma). En una
máquina nueva sigue haciendo falta: `git pull` → `terraform init` → `terraform plan` (tiene que
decir `No changes`). Y ojo con el `.terraform.lock.hcl`, que hoy solo tiene el hash `h1:` de
`linux_amd64`: para usarlo desde Windows hay que declarar las dos plataformas con
`terraform providers lock -platform=linux_amd64 -platform=windows_amd64`, no dejarlo librado a
desde dónde se corrió el `init` (ver bitácora §3, tercer bloque).

El `terraform.tfstate` local quedó en disco como respaldo de la migración. No borrarlo hasta la
Fase 9.
