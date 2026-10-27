# shellcheck shell=bash
# Claude Code harness (Anthropic).
# Installs the claude CLI globally via npm.
# Version pinned: 2.1.310 (update deliberately, check security advisories)
RUN npm install -g @anthropic-ai/claude-code@2.1.310 && \
    npm cache clean --force
