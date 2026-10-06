# ---- Stage 1: build the jar ------------------------------------------------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /workspace
ENV MAVEN_OPTS="-Xmx384m"

# Resolve dependencies first so this layer is cached while only the sources change
COPY pom.xml .
COPY config config
RUN mvn -B -q dependency:go-offline

COPY src src
# Tests already ran in the pipeline (Test / Coverage Gate stages): do not repeat them here
RUN mvn -B -q package -DskipTests

# ---- Stage 2: slim runtime image -------------------------------------------
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app
COPY --from=build /workspace/target/turnos-api.jar app.jar
USER app

# Cap the JVM so several containers fit in a small Docker Desktop VM
ENV JAVA_TOOL_OPTIONS="-Xmx192m -Xss512k" \
    APP_ENV=local
EXPOSE 8080

# wget exists in alpine (busybox): lets 'docker ps' show health status
HEALTHCHECK --interval=15s --timeout=3s --start-period=40s --retries=5 \
  CMD wget -qO- http://localhost:8080/actuator/health | grep -q UP || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
