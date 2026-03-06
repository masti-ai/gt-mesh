FROM ubuntu:22.04

ARG DOLT_VERSION=1.35.0

RUN apt-get update && apt-get install -y \
    bash curl git cron jq python3 \
    && rm -rf /var/lib/apt/lists/*

# Install Dolt
RUN curl -L https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/install.sh | bash

# Create gt user
RUN useradd -m -s /bin/bash gt

# Set up directory structure
RUN mkdir -p /home/gt/gt/.gt-mesh /home/gt/gt/plugins \
    && chown -R gt:gt /home/gt

USER gt
WORKDIR /home/gt/gt

# Copy mesh scripts and config
COPY --chown=gt:gt scripts/ .gt-mesh/scripts/
COPY --chown=gt:gt mesh-config/ .gt-mesh/mesh-config/
COPY --chown=gt:gt docker/entrypoint.sh /home/gt/entrypoint.sh

ENV GT_ROOT=/home/gt/gt
ENV MESH_YAML=/home/gt/gt/mesh.yaml
ENV PATH="/home/gt/.local/bin:${PATH}"

# Create gt-mesh CLI wrapper
RUN mkdir -p /home/gt/.local/bin && \
    printf '#!/bin/bash\nGT_ROOT="${GT_ROOT:-/home/gt/gt}"\nMESH_YAML="${MESH_YAML:-$GT_ROOT/mesh.yaml}"\nexport GT_ROOT MESH_YAML\nexec bash "$GT_ROOT/.gt-mesh/scripts/mesh.sh" "$@"\n' > /home/gt/.local/bin/gt-mesh && \
    chmod +x /home/gt/.local/bin/gt-mesh

ENTRYPOINT ["/home/gt/entrypoint.sh"]
CMD ["sync-loop"]
