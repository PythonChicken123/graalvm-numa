# ----------------------------------
# Pterodactyl Core Dockerfile
# Environment: Java (GraalVM with NUMA support)
# Minimum Panel Version: 1.7.0
# Base: Debian Bookworm Slim
# Permissions: Root
# ----------------------------------
FROM debian:bookworm-slim

ARG TARGETPLATFORM
ARG GRAAL_VERSION=24.0.2
ARG JAVA_VERSION=24

LABEL maintainer="EchoRuins, <contact@echoruins.com>"

ENV DEBIAN_FRONTEND=noninteractive

# Default to UTF-8 file.encoding
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
        curl ca-certificates openssl git tar sqlite3 fontconfig tzdata locales iproute2 \
        jq unzip lsof \
        # NUMA library (optional, but installed so the JVM can find it)
        libnuma1 \
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && case ${TARGETPLATFORM} in \
         "linux/amd64")  ARCH=x64  ;; \
         "linux/arm64")  ARCH=aarch64  ;; \
       esac \
    && curl --retry 3 -Lfso /tmp/graalvm.tar.gz \
        "https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-${GRAAL_VERSION}/graalvm-community-jdk-${GRAAL_VERSION}_linux-${ARCH}_bin.tar.gz" \
    && mkdir -p /opt/java/graalvm \
    && cd /opt/java/graalvm \
    && tar -xf /tmp/graalvm.tar.gz --strip-components=1 \
    && export PATH="/opt/java/graalvm/bin:$PATH" \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/graalvm.tar.gz

ENV JAVA_HOME=/opt/java/graalvm \
    PATH="/opt/java/graalvm/bin:$PATH"

# Create a tiny helper to check NUMA availability (returns 0 if NUMA works)
RUN echo '#!/bin/bash\n/opt/java/graalvm/bin/java -XX:+UseNUMA -version 2>&1 | grep -q "NUMA support enabled" && exit 0 || exit 1' > /usr/local/bin/check-numa \
    && chmod +x /usr/local/bin/check-numa

# Download MCAntiMalware (latest release, fallback to known version)
RUN curl -L -o /MCAntiMalware.jar https://github.com/OpticFusion1/MCAntiMalware/releases/latest/download/MCAntiMalware.jar \
    || curl -L -o /MCAntiMalware.jar https://github.com/OpticFusion1/MCAntiMalware/releases/download/v2.3/MCAntiMalware.jar \
    && if [ ! -f /MCAntiMalware.jar ] || [ $(stat -c%s /MCAntiMalware.jar) -lt 100000 ]; then \
         echo "ERROR: Failed to download MCAntiMalware" && exit 1; \
       fi

# Step 2 - add pterodactyl user
RUN useradd -d /home/container -m container

WORKDIR /home/container

COPY ./../entrypoint.sh /entrypoint.sh

CMD ["/bin/bash", "/entrypoint.sh"]
