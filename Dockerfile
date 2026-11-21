# Colanode Server wrapper for Railway. The stock image reads a JSON file named by CONFIG, listens on a fixed port 3000, leaves new accounts
# unverified or open depending on that file, and has no way to create the first account without an emailed code or open registration.
# This image writes the config from the Railway variables (Postgres, Redis, files on a volume at /data, registration needs an administrator's
# approval), starts the stock server, and once its migrations have run seeds an active administrator from COLANODE_ADMIN_EMAIL /
# COLANODE_ADMIN_PASSWORD (once, only when no such account exists).
# upstream: colanode/colanode
FROM ghcr.io/colanode/server:0.4.7@sha256:7006cac874fd5a154425108b9c7e6d6d9d117933c3694820b1a4c28aeb10008c

COPY --chmod=0755 boot.sh /railway-boot.sh

EXPOSE 3000
ENTRYPOINT ["/railway-boot.sh"]
CMD ["node", "apps/server/dist/index.js"]
