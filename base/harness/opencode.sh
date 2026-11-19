# shellcheck shell=bash
# OpenCode harness.
# Installs the opencode CLI globally via npm.
# Version pinned: 2.3.0 (update deliberately, check security advisories)
RUN npm install -g @opencode/cli@2.3.0 && \
    npm cache clean --force
