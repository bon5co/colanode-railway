# colanode-railway

Wrapper image for [Colanode](https://github.com/colanode/colanode) (open-source, local-first Slack and Notion alternative: chat, pages, databases and files in one workspace) on Railway.

It runs the official `ghcr.io/colanode/server` image, pinned by digest. The stock image needs a JSON config file and has no way to create the first account without an emailed code. This wrapper writes that config from plain Railway variables (PostgreSQL with pgvector, Redis, files on a volume at `/data`, account verification set to manual), starts the stock server, and once its migrations have run seeds one active administrator with a password from `COLANODE_ADMIN_EMAIL` and `COLANODE_ADMIN_PASSWORD` (only when no such account exists). Anyone else who registers is left pending until an administrator verifies the account.

Needs PostgreSQL 17 with pgvector and Redis alongside it; the Railway template wires all three. Licence of this wrapper: MIT. Colanode itself is Apache-2.0, see its own repository.
