# shellcheck shell=bash
# Pi coding agent harness (@earendil-works/pi-coding-agent).
# Installed via npm with --ignore-scripts (per pi's docs recommendation).
# Version pinned: 1.4.0 (update deliberately, check security advisories)
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent@1.4.0 && \
    npm cache clean --force
