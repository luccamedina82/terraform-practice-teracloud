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
- **Escribo yo el HCL, vos revisás.** No generes archivos completos sin que los haya pedido
  explícitamente. Si te pido revisión, señalá qué está mal y por qué, no lo reescribas entero.
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
| Perfil AWS | `default` |
| Entorno local | WSL Ubuntu 26.04. Terraform v1.15.8 en `~/.local/bin` (binario, no `apt`) |
| Repo | `/mnt/c/Users/lucca/desktop/teracloud/terraform` — se edita desde Windows, se ejecuta desde WSL |

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
| 2 — Red | pendiente |
| 3 — Migración a backend S3 | pendiente |
| 4 — ECR + push de la imagen | pendiente |
| 5 — IAM | pendiente |
| 6 — EC2 + user_data | pendiente |
| 7 — DNS | pendiente |
| 8 — Drift e import | pendiente |
| 9 — Cierre y destroy | pendiente |

**Decisiones abiertas**: qué juego / imagen Docker y en qué puerto corre (muerde en Fase 4).

**Cerradas en Fase 0**: bucket de estado `tf-state-workshop-lm-104981180500` · perfil AWS
`default` · Terraform por binario en `~/.local/bin` en vez de `apt` (ver bitácora §3).

**Ojo — todo lo que pida `sudo` o input interactivo lo tenés que correr vos en una terminal
real**: lo que lanzo yo va sin TTY y se cuelga sin devolver error. Aplica también a
`terraform apply` sin `-auto-approve`, que pide el `yes` por el mismo canal.
