# turnos-api: pipeline CI/CD completo en un Jenkins propio

La misma idea de pipeline que en GitHub Actions, pero sobre infraestructura que usted controla: **el pipeline es codigo** (`Jenkinsfile`), **el servidor de CI tambien es codigo** (Docker + Configuration as Code) y **una persona decide cuando produccion recibe el artefacto ya probado**.

La aplicacion es una API de turnos (Java 17, Spring Boot 3.5, Maven, H2). Lo importante no es la API sino el camino que recorre un commit hasta llegar a produccion.

## Levantar Jenkins (3 comandos)

Requisitos: Docker Desktop en marcha y los puertos libres `8090`, `5001`, `8081`, `8082`.

```bash
cd turnos-api                      # raiz del repositorio (el compose monta esta carpeta)
docker compose up -d --build       # primera vez: construye la imagen de Jenkins (varios minutos)
# con la imagen ya construida, Jenkins queda usable en ~1-2 minutos: abrir la URL de abajo
```

| Dato | Valor |
|------|-------|
| URL | http://localhost:8090 |
| Usuario / clave | `admin` / `admin` |
| Registro local de imagenes | http://localhost:5001/v2/_catalog |

> **Credencial de demostracion.** `admin/admin` es un usuario descartable, valido solo para esta laptop de clase. Esta escrito en `jenkins/casc.yaml` a proposito: en un entorno real las credenciales van en un gestor de secretos, nunca en el repositorio.

El job `turnos-api` **ya existe** al arrancar (lo crea `jenkins/casc.yaml`, sin pasos manuales) y revisa el repositorio local **cada minuto** (`pollSCM`). Como no hay build previo, la primera consulta dispara la primera ejecucion sola.

## Como se corresponden las 7 etapas con el `Jenkinsfile`

| # | Etapa del material | Stage del `Jenkinsfile` | Que hace |
|---|--------------------|-------------------------|----------|
| 1 | Checkout | `Checkout` | Clona el repo y calcula la etiqueta `<version>-<build>-<sha corto>` |
| 2 | Build | `Build` | `mvn clean package -DskipTests` |
| 3 | Testing automatizado | `Test` | Unitarios (Mockito) e integracion (`@SpringBootTest` + H2); publica JUnit. Si falla, **el pipeline se corta aca** |
| 3 | Cobertura / quality gate | `Coverage Gate` | JaCoCo: falla si la cobertura de lineas es menor a 80 % y publica el reporte |
| 4 | Analisis estatico | `Static Analysis` | PMD con un ruleset explicito (`config/pmd-ruleset.xml`) |
| 5 | Empaquetado | `Package` | `docker build` multi-stage; imagen inmutable con la etiqueta de version |
| 6 | Release / publicacion | `Publish` | `docker push` al registro local `localhost:5001` |
| 7a | Deploy automatico | `Deploy Staging` | Contenedor `turnos-staging` (puerto 8081), espera `/actuator/health` y hace smoke test |
| 7b | Deploy con aprobacion | `Approval` + `Deploy Production` | `input` humano; luego `turnos-prod` (puerto 8082) con health check y **rollback automatico** a la imagen anterior si falla |

Ademas: `post { success / failure }` imprime una notificacion **simulada** (un `echo`) y siempre se archiva el `.jar`.

## Guion de demostracion para el docente

Mantenga abierta la vista del job: http://localhost:8090/job/turnos-api/

### 1. Primera ejecucion y Stage View
- **Hacer:** abrir el job y esperar el build #1 (arranca solo). Entrar a *Console Output* un momento.
- **Observar:** cada columna del *Stage View* es un stage del `Jenkinsfile`; la corrida se **detiene en `Approval`** (franja azul). En el primer build el tiempo es largo porque se descargan dependencias Maven; despues es de ~1,5 minutos.
- **Verificar:** `curl localhost:8081/api/version` responde `"env":"staging"`; `curl localhost:5001/v2/turnos-api/tags/list` muestra la etiqueta `1.0.0-1-<sha>`.

### 2. Un commit dispara el build solo
```bash
git commit --allow-empty -m "chore: trigger pipeline"
```
- **Observar:** en menos de un minuto aparece un build nuevo, sin tocar Jenkins ni GitHub (no hay webhook: es *polling* del repositorio local). Aclarar que solo ven los cambios **commiteados**, no los del directorio de trabajo.
- Si el build anterior sigue esperando en `Approval`, el nuevo queda en cola (`disableConcurrentBuilds`): aprobar o abortar el anterior.

### 3. Romper un test: falla temprano
Editar cualquier test (por ejemplo, cambiar un `assertThat(...)` por un valor erroneo) y:
```bash
git commit -am "test: break on purpose"
```
- **Observar:** el pipeline falla en `Test`; `Coverage Gate`, `Package`, `Publish` y los deploys **no se ejecutan** (en la consola: `Stage "Package" skipped due to earlier failure(s)`). No aparece ninguna etiqueta nueva en el registro y se imprime `[SIMULATED NOTIFICATION] ... FAILED`.
- **Recuperar:** `git revert HEAD --no-edit` (o `git reset --hard HEAD~1` si se prefiere historia limpia). El siguiente build vuelve a verde.

### 4. Aprobar vs abortar en `Approval`
- **Hacer:** con un build pausado, pulsar **Deploy to production** (o **Abort**).
- **Observar:** al aprobar corre `Deploy Production`. Al abortar, el build queda `ABORTED` y produccion sigue con la imagen anterior.
- **Comparar:**
```bash
curl localhost:8081/api/version   # {"env":"staging","version":"1.0.0"}
curl localhost:8082/api/version   # {"env":"production","version":"1.0.0"}
docker ps --format "{{.Names}}  {{.Image}}"
```
Es **la misma imagen** (misma etiqueta) con distinta variable `APP_ENV`: se construye una vez y se promueve, no se reconstruye por ambiente.

### 5. De Continuous Delivery a Continuous Deployment
Eliminar del `Jenkinsfile` el stage `Approval` completo. Con eso, todo commit verde llega a produccion sin intervencion humana. Discutir que riesgo se asume (los tests y el quality gate pasan a ser la unica barrera) y que madurez de pruebas se necesita.

### 6. Jenkins vs GitHub Actions

| Aspecto | Jenkins (este caso) | GitHub Actions |
|---------|---------------------|----------------|
| Quien lo aloja | Usted (su servidor / laptop) | GitHub (SaaS) |
| Formato de configuracion | `Jenkinsfile` (Groovy declarativo) + plugins y JCasC | YAML en `.github/workflows/` |
| Disparadores | Webhook, `pollSCM`, manual, cron | `push`, `pull_request`, `schedule`, manual, etc. |
| Costo / mantenimiento | Software gratis, pero hay que operarlo: actualizaciones, plugins, parches, disco | Sin infraestructura; cuota gratuita y luego pago por minutos |
| Cuando elegirlo | Redes cerradas, requisitos de datos on-premise, pipelines muy personalizados, ya existe un Jenkins | Repos en GitHub, equipos chicos, arranque rapido, poco personal de operaciones |

## Estructura

```
Jenkinsfile                 # pipeline como codigo
docker-compose.yml          # Jenkins (8090) + registro (5001) + red turnos-net
jenkins/                    # Dockerfile, plugins.txt, casc.yaml (Jenkins como codigo)
scripts/deploy.sh           # deploy + health check + rollback
Dockerfile                  # imagen de la app (multi-stage, usuario no root)
config/pmd-ruleset.xml      # reglas de analisis estatico
src/                        # API y tests
```

Probar la app sin Jenkins: `mvn -B verify` (tests + gate de cobertura + PMD).

## Decisiones y simplificaciones de la demo

- **Jenkins corre como `root`** y monta `/var/run/docker.sock`: asi el pipeline usa el Docker del anfitrion. Es una simplificacion de clase; quien accede a Jenkins controla el Docker de la maquina.
- **Sin bind mounts en el pipeline:** el CLI de Docker esta dentro del contenedor pero el demonio esta en el anfitrion, por lo que un `-v ruta:...` se resolveria en el anfitrion y no encontraria los archivos. `docker build` funciona porque el contexto se envia por el socket.
- **Memoria acotada:** Jenkins con `-Xmx512m`, aplicaciones con `-Xmx192m` y limite de contenedor de 256 MB.
- **Registro local sin TLS:** `localhost:5001` es aceptado por Docker como registro inseguro (rango `127.0.0.0/8`). Funciona asi en Docker Desktop sin configuracion extra.
- **Notificacion simulada:** es un `echo`; en un caso real seria Slack, correo, etc.

## Problemas conocidos y soluciones

| Sintoma | Causa | Solucion |
|---------|-------|----------|
| El stage `Checkout` falla con `detected dubious ownership in repository` | El repo montado pertenece a otro usuario | Ya resuelto en `jenkins/Dockerfile` (`git config --system safe.directory '*'`). Si cambia la imagen base, reaplicar |
| `Checkout` falla por checkout local bloqueado (`file://` no permitido) | Jenkins bloquea repos locales por seguridad | Ya resuelto con `-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true` en `JAVA_OPTS` |
| El deploy quedaba colgado en la espera de salud cuando el contenedor se caia | `curl` sin tiempo maximo sobre un nombre que ya no resuelve | Corregido en `scripts/deploy.sh` (`--max-time 3` y corte si el contenedor no esta corriendo) |
| `docker push` a `localhost:5001` falla | Puerto ocupado o registro caido | `docker compose ps`; si fuera necesario agregar `localhost:5001` a `insecure-registries` |
| `mvn verify` falla en el host con `Could not transfer artifact ... .tmp` | Descarga concurrente al mismo `~/.m2` (varios procesos Maven a la vez) | Reintentar el comando |
| Un build nuevo no arranca | Hay otro build pausado en `Approval` (`disableConcurrentBuilds`) | Aprobar o abortar el anterior |
| El build no detecta mis cambios | `pollSCM` solo ve **commits** del repo | `git commit` antes de esperar |
| En el Stage View los stages omitidos aparecen como fallidos | Es la vista de Jenkins: la consola dice `skipped due to earlier failure(s)` | Explicarlo; no se ejecutaron |
| En consola: `triggers is deprecated` / `duplicates one seen earlier for admin` | Avisos inofensivos de Job DSL / usuarios | Ignorar |
| Con `curl` desde Git Bash, las URL con `[ ]` no funcionan | Globbing | Usar `curl -g` |
| Rutas con `-v` en Git Bash se deforman | Conversion de rutas de MSYS | `MSYS_NO_PATHCONV=1` y `$(pwd -W)` |

## Limpieza

```bash
docker rm -f turnos-staging turnos-prod        # contenedores creados por el pipeline
docker compose down                             # detiene Jenkins y el registro (conserva datos)
docker compose down -v                          # ademas borra jenkins_home y el registro (historial de builds)
docker network rm turnos-net                    # solo si quedo huerfana
```

Las imagenes `turnos-jenkins:1.0` y `localhost:5001/turnos-api:*` quedan en Docker; borrarlas con `docker image rm` si se necesita espacio.
