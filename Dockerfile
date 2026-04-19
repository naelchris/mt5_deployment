FROM gmag11/metatrader5_vnc:latest

# Pre-installed Wine+MT5 config — populated by the build-mt5-image workflow.
# Mounted at /config-base so it doesn't conflict with the /config bind-mount
# used at runtime.
COPY config-base /config-base

COPY docker-entrypoint-wrapper.sh /entrypoint-wrapper.sh
RUN chmod +x /entrypoint-wrapper.sh

ENTRYPOINT ["/entrypoint-wrapper.sh"]
