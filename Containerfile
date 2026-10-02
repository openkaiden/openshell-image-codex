#
# Copyright (C) 2026 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

# ghcr.io/openkaiden/openshell-image-base-builder:next
FROM ghcr.io/openkaiden/openshell-image-base-builder@sha256:27c5cb3411afcd4950ec89308425d54685a7c07b8de094260e8e92c0c9c9e43e AS builder
# codex-acp depends on a given range of codex versions (see @openai/codex in its package.json):
# CODEX_VERSION must stay in the range accepted by CODEX_ACP_VERSION
ARG CODEX_VERSION=0.159.3
ARG BUN_VERSION="bun-v1.4.2"
ARG CODEX_ACP_VERSION=v2.1.1
ARG CODEX_ACP_SHA=68d7d2d5ddfc0ed5746f9f6130892dda685e65dd

# Install Codex and then copy its whole package (codex needs codex-package.json, rg, bwrap, etc.
# next to its binary) inside the root filesystem
RUN set -eux; \
    curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh -s -- --release "${CODEX_VERSION}"; \
    mkdir -p /mnt/rootfs/usr/local/lib /mnt/rootfs/usr/local/bin; \
    cp -a "$(readlink -f /root/.codex/packages/standalone/current)" /mnt/rootfs/usr/local/lib/codex; \
    ln -s ../lib/codex/bin/codex /mnt/rootfs/usr/local/bin/codex; \
    # the codex app-server daemon invokes ps to track its process
    dnf install -y --installroot /mnt/rootfs --setopt=reposdir=/etc/yum.repos.d --setopt=install_weak_deps=False --nodocs procps-ng; \
    dnf clean all --installroot /mnt/rootfs

# Build the ACP adapter with bun and copy it inside the root filesystem
RUN set -eux; \
    dnf install -y git unzip; \
    curl -fsSL https://bun.com/install | bash -s -- "${BUN_VERSION}"; \
    install -D -m 0755 "$(readlink -f /root/.bun/bin/bun)" /usr/local/bin/bun; \
    # clone the ACP tag and check it still points to the expected commit
    git clone --depth 1 --branch "${CODEX_ACP_VERSION}" https://github.com/agentclientprotocol/codex-acp /tmp/codex-acp; \
    test "$(git -C /tmp/codex-acp rev-parse HEAD)" = "${CODEX_ACP_SHA}"; \
    cd /tmp/codex-acp; \
    bun install; \
    bun build --compile src/index.ts --outfile /mnt/rootfs/usr/local/bin/codex-acp

# Now create our final image with reduced layers
FROM scratch
COPY --from=builder /mnt/rootfs/ /
# Notify the ACP adapter where the codex binary is located
ENV CODEX_PATH=/usr/local/bin/codex
CMD ["codex"]
