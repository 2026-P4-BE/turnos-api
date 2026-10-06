# Pinned: "lts-jdk17" moves every few weeks and would change the server under our feet
FROM jenkins/jenkins:2.541.3-lts-jdk17

USER root

# Maven (the pipeline builds with it). Debian package: its version follows the pinned base image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends maven \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI only (static binary). The daemon is the HOST one, reached through the mounted socket.
ARG DOCKER_VERSION=27.4.0
RUN ARCH="$(uname -m)" \
    && curl -fsSL "https://download.docker.com/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz" \
       | tar -xz --strip-components=1 -C /usr/local/bin docker/docker \
    && docker --version

# The repo is mounted from the host with a different owner: without this git
# fails with "detected dubious ownership in repository"
RUN git config --system --add safe.directory '*'

# Plugins are pinned by name and version in plugins.txt and installed at build time (no UI clicks)
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Jenkins configuration as code
COPY casc.yaml /usr/share/jenkins/casc.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc.yaml
