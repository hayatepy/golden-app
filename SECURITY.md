# Security policy

This repository is a reference application and is not a substitute for a
deployment-specific threat model.

Report a vulnerability privately through GitHub's **Security → Report a
vulnerability** flow for this repository. Do not include Access JWTs,
credentials, D1 contents, or personal data in a public issue.

Before production use:

- complete every item in [PRODUCTION.md](PRODUCTION.md);
- replace every placeholder in `wrangler.toml`;
- use a Cloudflare Access application and explicit allow policy;
- define secrets, logging/retention, migration, rollback, and incident owners;
- review dependency and release attestations for the versions actually
  deployed.

The local email-header trust path is enabled only by an ignored `.dev.vars`
with `ENVIRONMENT=local`. Never deploy that local setting.
