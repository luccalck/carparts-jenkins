FROM node:24-bookworm-slim AS node
FROM docker:29-cli AS dockercli
FROM jenkins/inbound-agent:jdk21
USER root
COPY --from=node /usr/local /usr/local
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv git curl ca-certificates \
    && python3 -m venv /opt/azure-cli \
    && /opt/azure-cli/bin/pip install --no-cache-dir azure-cli==2.90.0 \
    && rm -rf /var/lib/apt/lists/*
ENV PATH="/opt/azure-cli/bin:${PATH}" AZURE_EXTENSION_USE_DYNAMIC_INSTALL=yes_without_prompt
RUN python3 -m venv /opt/aws-cli && /opt/aws-cli/bin/pip install --no-cache-dir awscli==1.46.1
ENV PATH="/opt/aws-cli/bin:${PATH}" AWS_PAGER=""
USER jenkins
