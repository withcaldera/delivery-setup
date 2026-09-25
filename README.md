# Caldera delivery setup

One-line Mac setup for Caldera delivery leads. It installs the tools Claude Code needs, signs you in to GitHub, and registers Caldera's private plugin marketplace.

Open **Terminal** (press ⌘-Space, type `Terminal`, press Return) and paste:

```
curl -fsSL https://raw.githubusercontent.com/withcaldera/delivery-setup/main/bootstrap.sh | bash
```

Step-by-step instructions with what each prompt looks like: [SETUP.md](SETUP.md).

This repo is public on purpose so the line above works before you have any credentials. It contains no secrets. The source of truth for `bootstrap.sh` is the private `withcaldera/delivery-plugin` repo under `setup/`; edit it there and copy it here.
