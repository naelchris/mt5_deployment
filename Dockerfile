FROM gmag11/metatrader5_vnc:latest

# Pre-installed Wine+MT5 — populated by the build-mt5-image workflow.
# Used only for seeding ./config on the host before the session container starts.
COPY config-base /config-base
