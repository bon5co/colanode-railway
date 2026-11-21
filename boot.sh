#!/bin/sh
# Colanode on Railway: write the server's config from the Railway variables, start the stock server (it migrates the database, then
# listens on its fixed port 3000), then seed an active administrator that can sign in with a password. Registration for anyone else
# is left on "manual": a stranger's account is created unverified and cannot sign in until an administrator verifies it.
set -eu
cd /app

need() { eval "v=\${$1:-}"; [ -n "$v" ] || { echo "[railway-boot] $1 is required" >&2; exit 1; }; }
for n in DB_HOST DB_USER DB_PASS DB_NAME REDIS_HOST REDIS_PASS COLANODE_ADMIN_EMAIL COLANODE_ADMIN_PASSWORD RAILWAY_PUBLIC_DOMAIN; do need "$n"; done
[ "${#COLANODE_ADMIN_PASSWORD}" -ge 8 ] || { echo "[railway-boot] COLANODE_ADMIN_PASSWORD must be at least 8 characters" >&2; exit 1; }
case "$COLANODE_ADMIN_EMAIL" in *[!A-Za-z0-9@._+-]*) echo "[railway-boot] COLANODE_ADMIN_EMAIL has characters outside A-Za-z0-9@._+-" >&2; exit 1;; esac

DATA_DIR="${COLANODE_DATA_DIR:-/data}"
mkdir -p "$DATA_DIR/files"
echo "[railway-boot] data directory $DATA_DIR owner=$(stat -c %u:%g "$DATA_DIR")"

export POSTGRES_URL="postgresql://$DB_USER:$DB_PASS@$DB_HOST:5432/$DB_NAME"
export REDIS_URL="redis://default:$REDIS_PASS@$REDIS_HOST:6379"
export CONFIG=/tmp/colanode-config.json
export NODE_ENV=production

cat > "$CONFIG" <<JSON
{
  "name": "${COLANODE_SERVER_NAME:-Colanode}",
  "web": { "domain": "$RAILWAY_PUBLIC_DOMAIN", "protocol": "https" },
  "mode": "standalone",
  "cors": { "origin": true, "maxAge": 7200 },
  "account": { "verificationType": "manual", "otpTimeout": 600 },
  "postgres": { "url": "env://POSTGRES_URL" },
  "redis": { "url": "env://REDIS_URL", "db": 0, "eventsChannel": "events" },
  "storage": {
    "tus": { "locker": { "type": "redis", "prefix": "colanode:tus:lock" }, "cache": { "type": "none" } },
    "provider": { "type": "file", "directory": "$DATA_DIR/files" }
  },
  "jobs": {
    "queue": { "name": "jobs", "prefix": "colanode" },
    "nodeUpdatesMerge": { "enabled": true },
    "documentUpdatesMerge": { "enabled": true },
    "cleanup": { "enabled": true }
  },
  "logging": { "level": "info" }
}
JSON
unset DB_PASS REDIS_PASS

"$@" &
SERVER=$!
trap 'kill -TERM "$SERVER" 2>/dev/null' TERM INT

# the server listens only after its migrations have run, so the account table exists once /config answers
n=0
until wget -q -O /dev/null "http://127.0.0.1:3000/config" 2>/dev/null; do
  kill -0 "$SERVER" 2>/dev/null || { wait "$SERVER"; exit $?; }
  n=$((n+1)); [ "$n" -le 300 ] || { echo "[railway-boot] server did not answer within 300s" >&2; kill "$SERVER"; exit 1; }
  sleep 1
done

# seed the administrator once: an active account with an argon2id hash (same parameters as the server's own sign-up);
# ON CONFLICT keeps a redeploy from overwriting a password the administrator changed
node -e '
const {hash}=require("@node-rs/argon2"),{Client}=require("pg"),{ulid}=require("ulid"),e=process.env;
(async()=>{
  const pw=await hash(e.COLANODE_ADMIN_PASSWORD,{memoryCost:19456,timeCost:2,parallelism:1});
  const c=new Client({connectionString:e.POSTGRES_URL});
  await c.connect();
  const r=await c.query("INSERT INTO accounts (id,name,email,password,status,created_at) VALUES ($1,$2,$3,$4,1,now()) ON CONFLICT (email) DO NOTHING",
    [ulid().toLowerCase()+"ac","Admin",e.COLANODE_ADMIN_EMAIL.toLowerCase(),pw]);
  console.log("[railway-boot] administrator "+e.COLANODE_ADMIN_EMAIL.toLowerCase()+(r.rowCount?" created":" already present"));
  await c.end();
})().catch(x=>{console.error("[railway-boot] seeding failed:",x.message);process.exit(1)});
'

wait "$SERVER"
