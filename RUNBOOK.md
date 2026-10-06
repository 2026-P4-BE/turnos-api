# RUNBOOK: clase de CI/CD con Jenkins propio (Unidad 5)

Guía para usar **durante la clase**. Dice qué ejecutar y, sobre todo, **qué explicar** en cada paso.
Qué es el repositorio y cómo está construido: [README.md](README.md).

Todos los comandos se ejecutan en **Git Bash**, desde la raíz del repositorio (`turnos-api/`).
Credenciales de Jenkins: `admin` / `admin`. URL: http://localhost:8090

| Necesito... | Comando |
|-------------|---------|
| Saber si todo está listo | `scripts/doctor.sh` |
| Levantar el laboratorio | `docker compose up -d --wait` |
| Volver al estado inicial (segundos) | `scripts/reset.sh` |
| Volver a un Jenkins nuevo de fábrica | `scripts/reset.sh --hard` |
| Ver / esperar / aprobar / abortar un build sin la interfaz | `scripts/jenkins.sh status \| wait \| approve \| abort \| log` |
| Disparar un ejercicio | `scripts/demo.sh trivial-change \| new-version \| break-test \| drop-coverage \| pmd-violation` |
| Reparar `main` con un commit nuevo | `scripts/demo.sh fix` |

---

## 0. Antes de la clase

**Estado en el que debería encontrar la máquina:** laboratorio **apagado y limpio** (sin contenedores, sin volúmenes de Jenkins ni de registro; solo quedan las imágenes y la caché de Maven), `main` en el tag `class-baseline`. Al levantarlo es un Jenkins nuevo: el build #1 arranca solo dentro del primer minuto. Si en cambio lo encuentra levantado con builds viejos: `scripts/reset.sh`.

- [ ] Docker Desktop abierto (ícono quieto). Cerrar otros laboratorios si hay poca memoria: Docker tiene 4 GB.
- [ ] Levantar: `docker compose up -d --wait` (25 a 40 s), luego `scripts/doctor.sh`. Con Jenkins apagado, `doctor.sh` marca `NOT READY` y lo indica.
- [ ] `scripts/doctor.sh` termina en `READY` (con advertencias si ya arrancó el build #1). Si dice `NOT READY`, cada línea `fix:` indica qué ejecutar.
- [ ] Si quedó algo de una clase anterior (advertencia de builds o commits): `scripts/reset.sh`.
- [ ] Abrir http://localhost:8090/job/turnos-api/ (ingresar con admin/admin) y dejarlo en pantalla.
- [ ] Tener a mano `Jenkinsfile`, `jenkins/casc.yaml`, `jenkins/Dockerfile` en el editor.
- [ ] Primer build sin ensayo previo: dejar que corra **antes** de que entren los alumnos (ver tiempos).

**Tiempos medidos en esta máquina** (Docker Desktop 4 GB, sin otras cargas pesadas):

| Qué | Tiempo |
|-----|--------|
| `scripts/doctor.sh` | ~7 s |
| Levantar con imagen ya construida y volúmenes vacíos | 25 a 36 s |
| Primer build tras un `--hard` (caché de Maven conservada) | ~1,7 min hasta `Approval` |
| Primer build con caché de Maven borrada (`--purge-cache`) | ~2,5 min hasta `Approval` |
| Build "tibio" hasta `Approval` | 65 a 80 s (más hasta 60 s de espera del sondeo) |
| Aprobar: `Deploy Production` | ~20 s |
| Build rojo en `Test` / `Coverage Gate` / `Static Analysis` | 42 s / 55 s / 69 s desde que arranca |
| Rollback real (`BREAK_PRODUCTION`) tras aprobar | ~20 s |
| `scripts/reset.sh` | 8 a 23 s |
| `scripts/reset.sh --hard` | 25 a 36 s |

---

## 1. Jenkins como código (sin ejecutar nada, 5 min)

**Objetivo:** que vean que el servidor de CI también es un artefacto versionado y reproducible.

**Qué explicar**
- "En GitHub Actions el servidor ya existe. Acá lo construimos nosotros, y lo construimos **como código**."
- `jenkins/Dockerfile`: imagen base **fijada** a una versión, Maven, CLI de Docker.
- `jenkins/plugins.txt`: plugins con **versión exacta**. Sin eso, reconstruir el servidor dentro de seis meses cambiaría el CI sin avisar.
- `jenkins/casc.yaml` (Configuration as Code): usuarios, URL y el **job semilla** que crea `turnos-api` al arrancar. Nadie hace clic para crearlo.
- `docker-compose.yml`: Jenkins + registro de imágenes + red, todo con un comando.

**Pasos**
1. Abrir `jenkins/casc.yaml`, bajar hasta `jobs:`. **Remarcar:** el job se define con `pipelineJob` y apunta al `Jenkinsfile` del repo. Con `scm('* * * * *')` consulta el repo cada minuto.
2. Abrir `jenkins/plugins.txt`. **Remarcar:** las primeras 8 líneas son las que pedimos; el resto son dependencias, también fijadas.
3. En Jenkins: *Manage Jenkins > Plugins > Installed*. **Qué deberían ver:** los mismos plugins. Nadie los instaló a mano.

**Preguntas**
- *¿Qué pasa si se rompe el servidor de CI?* Se reconstruye con un comando; no hay "el Jenkins de Juan que nadie sabe configurar".
- *¿Por qué fijar versiones?* Reproducibilidad: el mismo principio que "en mi máquina funciona" para el pipeline.

**Si algo falla:** no hace falta que Jenkins esté corriendo para este bloque; mostrar los archivos.

---

## 2. El `Jenkinsfile`, etapa por etapa (10 min)

**Objetivo:** mapear cada `stage` a las 7 etapas del material.

**Qué explicar**
- "El pipeline es una secuencia automatizada disparada por un evento (acá, un commit)."
- Declarativo: se lee de arriba a abajo; cada `stage` es una caja del Stage View.
- Falla temprano: una etapa roja corta todas las siguientes.

| # material | Etapa del material | `stage` | Qué remarcar |
|---|---|---|---|
| 1 | Checkout | `Checkout` | Trazabilidad: se construye desde un estado limpio del repo; la etiqueta de la imagen lleva build y commit |
| 2 | Build | `Build` | Entorno limpio y reproducible; "en mi máquina funciona" deja de valer |
| 3 | Testing automatizado | `Test` | Unitarios + integración (H2). Feedback inmediato |
| 3 | Quality gate | `Coverage Gate` | Falla por debajo de 80 %. "Cobertura alta no garantiza calidad; baja indica riesgo" |
| 4 | Análisis estático | `Static Analysis` | PMD examina el código **sin ejecutarlo** y puede bloquear. Otros: SonarQube, CodeQL |
| 5 | Empaquetado | `Package` | Imagen Docker multi-etapa, inmutable: lo probado es lo desplegado |
| 6 | Release | `Publish` | Push al registro con etiqueta de versión, solo si todo lo anterior pasó |
| 7 | Deploy | `Deploy Staging`, `Approval`, `Deploy Production` | Entornos definidos, aprobación manual, health check y rollback |

**Pasos**
1. Abrir `Jenkinsfile`. Señalar `options`: `disableConcurrentBuilds`, `timeout`, y que **la lógica pesada vive en `scripts/deploy.sh`**, no en el pipeline.
2. Señalar `post { success / failure }`: la notificación es **simulada** (un `echo`). En la práctica sería Slack o correo ("avisar al equipo cuando falla").
3. Señalar que **CI son las etapas 1 a 4**; 5 a 7 son entrega.

**Preguntas**
- *¿Por qué `Test` va antes de `Package`?* No tiene sentido empaquetar algo que ya sabemos roto; además es más barato fallar temprano.
- *¿Por qué se publica antes de desplegar?* El deploy toma la imagen **del registro**: es el artefacto oficial.

---

## 3. Demo 1: primer build y Stage View (8 min)

**Objetivo:** ver el pipeline completo hasta la aprobación.
**Tiempo:** build #1 hasta `Approval`: 1,5 a 2,5 min.

**Qué explicar**
- "Nadie creó el job ni apretó *Build*: el job apareció al arrancar y detectó que no había builds."
- Cada columna del Stage View es un `stage`.
- Va a detenerse en `Approval`: es **Continuous Delivery**, un humano decide producción.

**Pasos**
1. Mostrar la pantalla del job. **Qué deberían ver:** build #1 en curso (o, si falta, `scripts/jenkins.sh build`).
2. Entrar a *Console Output* un momento. **Remarcar:** cada comando que escribimos en el `Jenkinsfile` aparece acá.
3. Esperar la franja azul en `Approval`. En terminal: `scripts/jenkins.sh status`. **Qué deberían ver:**
   `Build #1: PAUSED_PENDING_INPUT` y `Approval=PAUSED_PENDING_INPUT` con todos los anteriores en `SUCCESS`.
4. Verificar staging y registro:
   ```bash
   curl localhost:8081/api/version                 # {"env":"staging","version":"1.0.0"}
   curl localhost:5001/v2/turnos-api/tags/list     # {"name":"turnos-api","tags":["1.0.0-1-<commit>"]}
   curl localhost:8082/api/version                 # falla: producción todavía no existe
   ```
   **Remarcar:** la etiqueta `versión-build-commit` identifica **exactamente** qué se desplegó. Producción aún no existe.

**Preguntas**
- *¿Qué hay en producción ahora?* Nada: nadie aprobó.
- *¿Por qué la etiqueta lleva el número de build y el commit?* Trazabilidad e inmutabilidad.

**Si algo falla**
- El build no arranca solo: `scripts/jenkins.sh build`.
- La interfaz no responde: todo se puede hacer con `scripts/jenkins.sh` (ver `status`, `log`, `approve`).
- Falla `Checkout` o `Package`: `scripts/doctor.sh` y, si hace falta, `scripts/reset.sh --hard`.

---

## 4. Demo 2: aprobar, y qué cambia en producción (4 min)

**Qué explicar**
- "La aprobación es una decisión humana sobre un artefacto **ya probado**: no se reconstruye nada."
- Después del deploy hay health check; si falla, vuelve a la versión anterior (demo 6).

**Pasos**
1. En la interfaz: clic en la caja `Approval` del Stage View > **Deploy to production**. Plan B: `scripts/jenkins.sh approve`.
2. Esperar ~20 s. **Qué deberían ver:** build #1 `SUCCESS`, y `[SIMULATED NOTIFICATION] Build #1 OK` al final de la consola.
3. ```bash
   curl localhost:8082/api/version     # {"env":"production","version":"1.0.0"}
   docker ps --format "{{.Names}}  {{.Image}}" | grep turnos-
   ```
   **Qué deberían ver:** `turnos-staging` y `turnos-prod` con **la misma imagen** (`...:1.0.0-1-<commit>`).
   **Remarcar:** misma imagen, distinta variable `APP_ENV`: se construye **una vez** y se promueve.

**Preguntas**
- *¿Qué cambia entre staging y producción?* Solo la configuración (`APP_ENV`), no el binario.

---

## 5. Demo 3: un commit dispara el build (5 min)

**Objetivo:** el evento es el commit, no un clic.

**Qué explicar**
- "Acá no hay webhook: Jenkins **pregunta** cada minuto si hay commits nuevos (*polling*). En GitHub Actions el evento `push` lo manda GitHub."
- "Solo ve commits, no cambios sin commitear."
- "Commits pequeños y frecuentes: feedback rápido."

**Pasos**
1. `scripts/demo.sh trivial-change` (crea un commit vacío marcado como demo).
2. `scripts/jenkins.sh wait next`. **Qué deberían ver:** líneas con cada stage pasando a `SUCCESS`, y `Paused at Approval after ~80s`.
   **Remarcar:** no se tocó Jenkins; apareció el build #2.
3. **Dejarlo pausado.** Es la base de la demo 4.

**Preguntas**
- *¿Por qué no arranca instantáneamente?* Es sondeo cada minuto; con webhook sería inmediato.

**Si algo falla:** si pasa más de 90 s sin build, `scripts/jenkins.sh status` (¿hay un build anterior pausado que bloquea?) o `scripts/jenkins.sh build`.

---

## 6. Demo 4: abortar en `Approval` (6 min)

**Objetivo:** staging con lo nuevo, producción con lo anterior.

**Qué explicar**
- "Mientras el build #2 espera, **bloquea a los siguientes** (`disableConcurrentBuilds`): un solo despliegue a la vez."
- "Abortar es una decisión válida: producción no se toca."

**Pasos**
1. Con #2 pausado, comparar imágenes: `docker ps --format "{{.Names}}  {{.Image}}" | grep turnos-`.
   **Qué deberían ver:** `turnos-staging ...:1.0.0-2-<commit>` y `turnos-prod ...:1.0.0-1-<commit>`.
2. Mostrar el bloqueo: `scripts/demo.sh new-version`, esperar 1 min y abrir el job. **Qué deberían ver:** el build nuevo **en cola** ("Build #2 is already in progress").
3. Abortar #2: botón **Abort** en el paso `Approval` (o `scripts/jenkins.sh abort 2`). **Qué deberían ver:** #2 `ABORTED`, `Deploy Production` no ejecutado; el build #3 arranca solo.
4. Esperar el `Approval` de #3: `scripts/jenkins.sh wait`.
   ```bash
   curl localhost:8081/api/version   # "version":"1.0.0-demo1"   <- lo nuevo
   curl localhost:8082/api/version   # "version":"1.0.0"         <- lo anterior
   ```
   **Remarcar:** staging adelantado, producción intacta.
5. **Aprobar #3** para dejar producción en `1.0.0-demo1` (`scripts/jenkins.sh approve`) y esperar que termine.

**Preguntas**
- *Si nadie contesta el `input`?* A los 30 min vence (`timeout`) y el build queda `ABORTED` para no bloquear la cola.
- *¿Por qué un solo build a la vez?* Evita dos despliegues pisándose en el mismo entorno.

**Si algo falla:** `scripts/jenkins.sh status` muestra qué build está pausado; `scripts/jenkins.sh abort N` lo libera.

---

## 7. Demo 5: rollback real en producción (6 min)

**Objetivo:** un despliegue malo llega a producción y el pipeline vuelve atrás solo.

**Qué explicar**
- "Pasó todas las pruebas, pero en producción hay una **configuración mala**. Los tests no lo ven."
- "Después del deploy se **monitorea la salud**: eso es la etapa 7 completa."
- Simulación: el parámetro `BREAK_PRODUCTION` arranca la versión nueva con una URL de base de datos inválida.

**Pasos**
1. Con producción sana (demo 4 terminada): en el job, **Build with Parameters** > marcar `BREAK_PRODUCTION` > **Build**. Plan B: `scripts/jenkins.sh build break-prod`.
   *(El parámetro aparece desde que corrió un build con este `Jenkinsfile`; tras reiniciar con `reset.sh` ya está.)*
2. Esperar `Approval` y aprobar. **Remarcar:** es el mismo artefacto que pasó staging sano.
3. Mirar la consola de `Deploy Production`. **Qué deberían ver:**
   ```
   BREAK_DEPLOY=true: injecting a bad configuration on purpose
   Deploying localhost:5001/turnos-api:1.0.0-4-<commit> as turnos-prod ...
   Health check FAILED for turnos-prod
   Caused by: java.lang.RuntimeException: Failed to load driver class org.postgresql.Driver ...
   Rolling back to localhost:5001/turnos-api:1.0.0-3-<commit>
   Rollback OK
   ```
   El build termina `FAILED` en `Deploy Production`.
4. `curl localhost:8082/api/version` responde `"version":"1.0.0-demo1"` y `docker ps` muestra la imagen del build #3. **Remarcar:** el cliente nunca estuvo sin servicio estable; el pipeline avisó que falló (`[SIMULATED NOTIFICATION] ... FAILED`).

**Preguntas**
- *¿Qué detectó el problema?* El health check de `/actuator/health` (y que el contenedor no siguiera corriendo).
- *¿Qué faltaría en un caso real?* Monitoreo continuo, despliegues graduales, alertas.

**Si algo falla:** si producción quedó caída, `scripts/reset.sh` la elimina junto con todo lo demás.

---

## 8. Demo 6: test roto, falla temprano (6 min)

**Qué explicar**
- "Un test rojo corta el pipeline en `Test`: no se empaqueta, no se publica, no se despliega."
- "Regla de CI: si `main` está rojo, se detiene todo y se arregla."

**Pasos**
1. `scripts/demo.sh break-test` y `scripts/jenkins.sh wait next`.
   **Qué deberían ver:** `Finished: FAILED after ~45s` y `Test=FAILED`.
2. En la consola: `expected: "Dr. Wilson"` y `Tests run: 5, Failures: 1`.
3. Confirmar que no hay etiqueta nueva: `curl localhost:5001/v2/turnos-api/tags/list`.
   **Remarcar:** la imagen **no existe**; lo roto no puede desplegarse.
4. Notar `[SIMULATED NOTIFICATION] ... FAILED`. En el Stage View, las etapas posteriores se muestran como no ejecutadas (la consola dice `skipped due to earlier failure(s)`). Aclararlo.
5. Reparar con un commit nuevo (lo normal en equipos): `scripts/demo.sh fix` y `scripts/jenkins.sh wait next`.
   **Qué deberían ver:** vuelve a verde y queda en `Approval`. **Abortarlo** (`scripts/jenkins.sh abort`) para no bloquear.

**Preguntas**
- *¿Por qué reparar con un commit en lugar de borrar el anterior?* El historial compartido no se reescribe.

---

## 9. Demo 7: quality gate de cobertura (5 min)

**Qué explicar**
- "El código nuevo **sin tests** baja la cobertura; el gate exige 80 %."
- "Los tests pasan y aun así el pipeline falla: son controles distintos."

**Pasos**
1. `scripts/demo.sh restore` (vuelve a `class-baseline`; sin build nuevo) y luego `scripts/demo.sh drop-coverage`.
2. `scripts/jenkins.sh wait next`. **Qué deberían ver:** `Test=SUCCESS`, `Coverage Gate=FAILED`.
3. Consola: `Rule violated for bundle turnos-api: lines covered ratio is 0.73, but expected minimum is 0.80`.
   **Remarcar:** el número exacto y el umbral; "una cobertura baja indica riesgo".

**Preguntas**
- *¿100 % de cobertura garantiza calidad?* No: mide líneas ejecutadas, no que las aserciones sean buenas.

---

## 10. Demo 8: análisis estático (4 min)

**Qué explicar**
- "El análisis estático mira el código **sin correrlo** y puede bloquear el build."

**Pasos**
1. `scripts/demo.sh restore` y `scripts/demo.sh pmd-violation`.
2. `scripts/jenkins.sh wait next`. **Qué deberían ver:** `Test=SUCCESS`, `Coverage Gate=SUCCESS`, `Static Analysis=FAILED`.
3. Consola: `PMD Failure: ...AppointmentService:36 Rule:SystemPrintln Priority:2 Usage of System.out/err.`
   **Remarcar:** acá pasan los tests y la cobertura; el problema es de **calidad/higiene** (un `println` de depuración).
4. `scripts/demo.sh restore` para dejar todo en su punto de partida.

**Preguntas**
- *Herramientas equivalentes en otros pipelines?* SonarQube, CodeQL, OWASP Dependency-Check.

---

## 11. De Continuous Delivery a Continuous Deployment (3 min, solo conversación)

**Qué explicar**
- **Continuous Delivery:** el artefacto siempre está listo; **una persona** decide producción (nuestro `Approval`).
- **Continuous Deployment:** todo cambio que pasa los controles llega a producción **sin paso humano**.
- Para pasar de una a otra: **borrar el `stage('Approval')` completo** del `Jenkinsfile`. Nada más.
- Qué se asume: los tests, el gate y el health check pasan a ser la **única** barrera. Requiere madurez de pruebas.

**Pregunta:** *¿Qué haría falta antes de quitar el `Approval`?* Pruebas fiables, despliegues reversibles (rollback), monitoreo.

---

## 12. Jenkins vs GitHub Actions (para decir en voz alta)

| Aspecto | Jenkins (este caso) | GitHub Actions |
|---------|---------------------|----------------|
| Quién lo aloja | Nosotros: servidor propio | GitHub (SaaS) |
| Configuración | `Jenkinsfile` (Groovy declarativo) + plugins + JCasC | YAML en `.github/workflows/` |
| Disparadores | Webhook, `pollSCM`, manual, cron | `push`, `pull_request`, `schedule`, manual |
| Costo / mantenimiento | Software gratis; hay que operarlo: actualizar, parchear, seguridad, disco | Sin infraestructura; cuota gratuita y luego por minuto |
| Cuándo elegirlo | Red cerrada, datos on-premise, pipelines muy a medida, ya existe Jenkins | Repos en GitHub, equipos chicos, arranque rápido, poco personal de operaciones |

Mensaje: **el modelo mental es el mismo** (eventos, etapas, artefactos, aprobaciones); cambia quién opera la infraestructura.

---

## 13. Volver al estado inicial

**Un solo punto de entrada: `scripts/reset.sh`.**

| | Suave (`scripts/reset.sh`) | Total (`scripts/reset.sh --hard`) |
|---|---|---|
| Tiempo | 8 a 23 s | 25 a 36 s |
| Jenkins | Sigue corriendo | Se destruye y se crea de nuevo |
| Builds en curso / en cola | Se abortan | Se descartan |
| Historial de builds | Se borra (próximo build: #1) | Se borra (volumen nuevo) |
| Contenedores `turnos-staging` / `turnos-prod` | Se eliminan | Se eliminan |
| Registro de imágenes e imágenes `turnos-api:*` | Se vacían | Se vacían |
| Commits de demo en `main` | Se deshacen | Se deshacen |
| Caché de Maven | Se conserva | Se conserva (`--purge-cache` la borra) |
| Cuándo usarlo | Entre ejercicios y entre clases | Jenkins en mal estado, o para probar el camino "clon nuevo" |

Opciones: `--keep-history` (suave: conserva la lista de builds), `--purge-cache` (total), `--rebuild` (total: reconstruye la imagen de Jenkins, requiere internet).

**Seguridad:** el reinicio de `main` solo ocurre si **todos** los commits posteriores al tag `class-baseline` los creó `demo.sh`. Si hay un commit propio o cambios sin commitear, **se niega y no toca nada**, y explica cómo seguir.

**Cómo confirmar:** el propio script termina con ocho líneas `[ OK ]` (Jenkins, job, historial vacío, sin builds, sin contenedores, registro vacío, sin imágenes, `main` en la base). Después `scripts/doctor.sh`.

**Después del reinicio**, el build #1 arranca solo en menos de un minuto (el job ve que no tiene builds). Para esperarlo: `scripts/jenkins.sh wait`.

---

## 14. Repetir la clase

- **Persiste entre clases:** imagen de Jenkins, caché de Maven (volumen `turnos-ci_maven_cache`), capas de Docker, el tag `class-baseline`, los scripts.
- **No persiste tras el reinicio:** historial, registro, contenedores, commits de demo.
- Orden recomendado: `doctor.sh` > (si hace falta) `reset.sh` > demos 1 a 8 en el orden de este documento.
- Si cambia el repositorio a propósito (por ejemplo, mejoras al código): commitear y mover la base con `scripts/demo.sh baseline`.
- Si pasó un semestre: `scripts/reset.sh --hard --rebuild` reconstruye Jenkins con las **mismas** versiones (están fijadas); probar antes de la clase y con internet.
- Memoria: no abrir otros laboratorios Docker pesados durante la clase.

---

## 15. Límites honestos de la simulación

Decirlo en clase: es una demo, **no** una configuración de producción.

- **Un solo anfitrión.** Jenkins, registro, staging y producción comparten la misma máquina y el mismo Docker. En la realidad son entornos separados.
- **Jenkins corre como `root` y monta `/var/run/docker.sock`.** Quien controla Jenkins controla el Docker de la máquina. Real: agentes dedicados o proxy del socket.
- **`admin` / `admin`** escrito en `casc.yaml`. Real: gestor de secretos, SSO; nunca credenciales en el repositorio.
- **Registro local sin TLS ni autenticación** (`localhost:5001`).
- **Sondeo cada minuto** en lugar de webhook.
- **Notificación simulada** (`echo`).
- **Producción es un contenedor**, sin balanceador, sin base de datos real (H2 en memoria: los datos se pierden al desplegar).
- **El "fallo" de producción es inyectado** por un parámetro.
