# Vibe harness (Mistral).
# Python-based, installed with uv system-wide (never into /home/agent —
# the run script mounts a tmpfs over it, which would mask it).
# HOME is redirected so uv's default tool paths land in /opt inside the
# image layer.
# Version pinned: 3.0.2 (update deliberately, check security advisories)
RUN mkdir -p /opt/uv-home && \
    HOME=/opt/uv-home uv tool install mistral-vibe==3.0.2 && \
    rm -rf /opt/uv-home/.cache
