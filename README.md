# turnos-api: pipeline CI/CD completo en un Jenkins propio

Caso de la Unidad 5 (UTN, Programación IV): la misma idea de pipeline que en GitHub Actions, pero sobre infraestructura propia. **El pipeline es código** (`Jenkinsfile`), **el servidor de CI también es código** (Docker + Configuration as Code) y **una persona decide cuándo producción recibe el artefacto ya probado**.

La aplicación es una API de turnos (Java 17, Spring Boot 3.5, Maven, H2). Lo importante no es la API sino el camino que recorre un commit hasta producción.

> **Para dar la clase, usar [RUNBOOK.md](RUNBOOK.md).** Este README explica qué es el repositorio y cómo está construido.

## Inicio rápido

Requisitos: Docker Desktop (4 GB para contenedores), Git Bash, puertos libres `8090`, `5001`, `8081`, `8082`.

```bash
docker compose up -d --build --wait   # primera vez: construye la imagen de Jenkins (necesita internet)
scripts/doctor.sh                     # comprueba que todo está listo
```

| Dato | Valor |
|------|-------|
| Jenkins | http://localhost:8090 (`admin` / `admin`) |
| Registro de imágenes | http://localhost:5001/v2/_catalog |
| Staging / Producción | http://localhost:8081 / http://localhost:8082 (los crea el pipeline) |

El job `turnos-api` **ya existe** al arrancar (lo crea `jenkins/casc.yaml`, sin pasos manuales) y consulta el repositorio local cada minuto (`pollSCM`). Sin builds previos, la primera consulta dispara el build #1 sola.

> **Credencial de demostración.** `admin/admin` está escrito en `jenkins/casc.yaml` a propósito: es un usuario descartable para esta laptop. En un entorno real van en un gestor de secretos.

## Arquitectura

```
 commit en main ──(pollSCM, 1 min)──> Jenkins (8090) ──Jenkinsfile──> Test / Gate / PMD
                                         │ docker.sock del anfitrión
                       docker build ─────┴──> registro local (5001) ──pull──> turnos-staging (8081)
                                                                       └─ aprobación ─> turnos-prod (8082)
```

| Pieza | Qué es |
|-------|--------|
| `turnos-jenkins` | Jenkins 2.541.3 LTS con Maven, CLI de Docker y plugins fijados. Usa el Docker **del anfitrión** por el socket |
| `turnos-registry` | `registry:2.8.3`, registro de imágenes local |
| `turnos-staging`, `turnos-prod` | Contenedores de la app que crea el pipeline (misma imagen, distinto `APP_ENV`) |
| red `turnos-net` | Permite a Jenkins llegar a las apps por nombre |
| `/repos/turnos-api` | El repositorio montado **solo lectura** dentro de Jenkins: lo que Jenkins ve son los **commits** de `main` |

### Etapas del `Jenkinsfile`

| # | Etapa del material | `stage` | Qué hace |
|---|--------------------|---------|----------|
| 1 | Checkout | `Checkout` | Clona el repo y calcula la etiqueta `<versión>-<build>-<commit>` |
| 2 | Build | `Build` | `mvn clean package -DskipTests` |
| 3 | Testing | `Test` | Unitarios (Mockito) e integración (`@SpringBootTest` + H2); publica JUnit |
| 3 | Quality gate | `Coverage Gate` | JaCoCo: falla bajo 80 % de líneas |
| 4 | Análisis estático | `Static Analysis` | PMD con `config/pmd-ruleset.xml` |
| 5 | Empaquetado | `Package` | `docker build` multi-etapa, imagen inmutable |
| 6 | Release | `Publish` | `docker push` a `localhost:5001` |
| 7 | Deploy | `Deploy Staging`, `Approval`, `Deploy Production` | `scripts/deploy.sh`: health check y rollback; `input` humano (vence a los 30 min y el build queda `ABORTED`) |

`post` imprime una notificación **simulada** y archiva el `.jar`. El parámetro `BREAK_PRODUCTION` (por defecto `false`) hace que el despliegue a producción arranque con una configuración inválida para mostrar el rollback.

## Reproducibilidad: qué está fijado y qué no

| Elemento | Estado |
|----------|--------|
| Imagen base de Jenkins | Fijada: `jenkins/jenkins:2.541.3-lts-jdk17` |
| Plugins de Jenkins | **Fijados con versión** en `jenkins/plugins.txt` (77, tomados del Jenkins en funcionamiento; verificado que una reconstrucción da la misma lista). Para actualizarlos, hacerlo a propósito y reprobar |
| CLI de Docker, registro | Fijados (`DOCKER_VERSION`, `registry:2.8.3`) |
| Maven del servidor | Paquete Debian: sigue a la imagen base fijada |
| Imágenes de la app (`maven:3.9-eclipse-temurin-17`, `eclipse-temurin:17-jre-alpine`) | **Etiquetas móviles** (versión menor). Aceptable para el caso; si se necesita bit a bit, fijar por digest |
| Fin de línea | `.gitattributes` fuerza LF en scripts, `Jenkinsfile`, Dockerfiles y YAML |

## Scripts

Todos funcionan desde cualquier directorio, usan solo herramientas de Git Bash y `curl` (con tiempo máximo), son idempotentes y terminan verificando el estado. No tocan nada ajeno al laboratorio (proyecto compose `turnos-ci`, contenedores `turnos-*`, imágenes `localhost:5001/turnos-api:*`).

| Script | Función |
|--------|---------|
| `scripts/doctor.sh` | Chequeo previo a la clase: Docker, imagen, puertos (libres o propios), contenedores, Jenkins, job, registro, git. Dice qué ejecutar si algo falla |
| `scripts/reset.sh` | Vuelve al estado inicial. Suave (por defecto, segundos) o `--hard` (Jenkins nuevo). Detalle en el RUNBOOK |
| `scripts/demo.sh` | Ejercicios como commits conocidos en `main` y su deshacer seguro (`restore`, `fix`, `baseline`, `status`) |
| `scripts/jenkins.sh` | `build`, `status`, `wait`, `approve`, `abort`, `log` por REST (crumb incluido) |
| `scripts/deploy.sh` | Lo usa el pipeline: despliega, espera `/actuator/health` y revierte si falla |
| `scripts/lib.sh` | Funciones comunes (no se ejecuta) |

**Cómo se protege el trabajo real:** `demo.sh restore` (y por tanto `reset.sh`) solo hace `git reset --hard class-baseline` si cada commit posterior al tag lo creó `demo.sh` (llevan la línea `Class-Demo:` en el mensaje) y no hay cambios sin commitear. Si no, se niega y explica. Para fijar un nuevo punto de partida: `scripts/demo.sh baseline`.

## Estructura

```
Jenkinsfile                 # pipeline como código
RUNBOOK.md                  # guion de la clase
docker-compose.yml          # Jenkins (8090) + registro (5001) + red turnos-net + volúmenes
jenkins/                    # Dockerfile, plugins.txt (versiones fijas), casc.yaml (JCasC + job semilla)
scripts/                    # doctor, reset, demo, jenkins, deploy, lib
Dockerfile                  # imagen de la app (multi-etapa, usuario no root)
config/pmd-ruleset.xml      # reglas de análisis estático
src/                        # API y tests
```

Volúmenes: `turnos-ci_jenkins_home` (configuración y builds), `turnos-ci_registry_data` (imágenes), `turnos-ci_maven_cache` (`/root/.m2`, evita bajar dependencias en cada contenedor nuevo).

Probar la app sin Jenkins: `mvn -B verify` (tests + gate de cobertura + PMD).

## Decisiones y simplificaciones

- **Jenkins corre como `root`** y monta `/var/run/docker.sock`: el pipeline usa el Docker del anfitrión. Quien accede a Jenkins controla ese Docker. Simplificación de clase.
- **Sin bind mounts en el pipeline:** el demonio está en el anfitrión, un `-v ruta:...` se resolvería allí. `docker build` funciona porque el contexto viaja por el socket.
- **Memoria acotada:** Jenkins `-Xmx512m`, Maven `-Xmx384m`, apps `-Xmx192m` con límite de 256 MB. No ejecutar varios builds en paralelo (`disableConcurrentBuilds`).
- **Registro local sin TLS:** Docker acepta `localhost:5001` como inseguro (rango `127.0.0.0/8`).
- **`pom.xml` intacto en los ejercicios:** cambiarlo invalida la caché de dependencias del `docker build` y suma minutos; por eso `new-version` modifica `application.properties`.
- **Acumulación:** cada build deja una imagen (~375 MB) en Docker y en el registro; nada las poda durante la clase. `reset.sh` las elimina (imágenes y registro). Las capas intermedias de `docker build` quedan en la caché de Docker: `docker builder prune` las libera (afecta a todo Docker; no se hace automáticamente).

## Problemas conocidos

| Síntoma | Causa | Solución |
|---------|-------|----------|
| `Checkout`: `detected dubious ownership` | El repo montado pertenece a otro usuario | Resuelto en `jenkins/Dockerfile` (`safe.directory`) |
| `Checkout`: checkout local bloqueado | Jenkins bloquea `file://` | Resuelto con `ALLOW_LOCAL_CHECKOUT=true` en `JAVA_OPTS` |
| Un build nuevo no arranca | Otro build pausado en `Approval` (`disableConcurrentBuilds`) | Aprobar o abortar (`scripts/jenkins.sh abort`); `scripts/reset.sh` los aborta todos |
| El build no ve mis cambios | `pollSCM` solo ve **commits** | Commitear y esperar hasta 1 min |
| Primer build lento tras `--purge-cache` | Descarga de dependencias Maven | Esperar ~2,5 min; sin `--purge-cache` la caché se conserva |
| Etapas posteriores a un fallo aparecen como fallidas en el Stage View | Presentación de Jenkins; la consola dice `skipped due to earlier failure(s)` | Explicarlo |
| `curl` desde Git Bash con `[ ]` en la URL no funciona | Globbing | `curl -g` |
| Rutas `/algo` pasadas a `docker` se deforman | Conversión de rutas de MSYS | `MSYS_NO_PATHCONV=1` (los scripts ya lo hacen) |
| Avisos `triggers is deprecated` / `duplicates one seen earlier for admin` | Job DSL / usuarios | Inofensivos |
| `Could not transfer artifact ... .tmp` en el anfitrión | Dos Maven a la vez sobre el mismo `~/.m2` | Reintentar |
| Puerto ocupado (`8090`, `5001`, `8081`, `8082`) | Otro programa o laboratorio | `scripts/doctor.sh` indica quién lo usa |

## Limpieza manual

`scripts/reset.sh --hard` cubre todo lo siguiente salvo el caché de Maven. Para apagar sin borrar datos: `docker compose down`. Para liberar espacio por completo: `scripts/reset.sh --hard --purge-cache`, luego `docker compose down` y `docker image rm turnos-jenkins:1.0`.
