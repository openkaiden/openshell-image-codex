#!/usr/bin/env bash
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

# Smoke test of the built image, run by the shared oci-image workflow once per platform.
# IMAGE and PLATFORM are provided by the workflow.
set -euo pipefail

expected=$(sed -n 's/^ARG CODEX_VERSION=//p' Containerfile)
version=$(podman run --rm --platform "${PLATFORM}" "${IMAGE}" codex --version)
echo "codex --version: ${version}"
[[ "${version}" == "codex-cli ${expected}" ]] || { echo "::error::expected codex-cli ${expected}, got ${version}"; exit 1; }

expected_acp=$(sed -n 's/^ARG CODEX_ACP_VERSION=v//p' Containerfile)
version_acp=$(podman run --rm --platform "${PLATFORM}" "${IMAGE}" codex-acp --version)
echo "codex-acp --version: ${version_acp}"
[[ "${version_acp}" == "@agentclientprotocol/codex-acp ${expected_acp}" ]] || { echo "::error::expected codex-acp ${expected_acp}, got ${version_acp}"; exit 1; }

# ACP initialize request. codex-acp exits as soon as its input is closed, without
# answering, so keep the input open until the response is there.
workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT
mkfifo "${workdir}/stdin"
timeout 120 podman run --rm -i --platform "${PLATFORM}" "${IMAGE}" codex-acp < "${workdir}/stdin" > "${workdir}/stdout" &
exec 3> "${workdir}/stdin"
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}' >&3

is_initialized() { jq -se 'any(.[]; .id == 1 and .result.protocolVersion == 1)' "${workdir}/stdout" > /dev/null 2>&1; }
for _ in $(seq 90); do
  is_initialized && break
  sleep 1
done
exec 3>&-
wait

echo "ACP response: $(cat "${workdir}/stdout")"
is_initialized || { echo "::error::invalid ACP initialize response"; exit 1; }

# Interactive codex starts the app-server daemon, which needs the full codex package and ps.
# A healthy TUI keeps running until timeout; a broken one exits right away with an error.
tui=$(timeout 20 podman run --rm -t --platform "${PLATFORM}" "${IMAGE}" timeout 10 codex 2>&1 || true)
if grep -q -e 'Error:' -e '--no-daemon' <<< "${tui}"; then
  echo "::error::codex failed to start: ${tui}"; exit 1
fi
