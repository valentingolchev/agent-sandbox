# OpenCode harness.
# Installs the opencode CLI globally via npm.
# Version pinned: 2.1.4 (update deliberately, check security advisories)
RUN npm install -g @opencode/cli@2.1.4 && \
    npm cache clean --force
