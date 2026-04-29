# Claude Code MiniMax API Setup for Linux

Copy and paste this into your Claude conversation on the Linux SSH host:

---

I need to set up Claude Code with MiniMax API on this Linux system. Please help me complete these steps:

## Environment Variables to Set

Set these environment variables in the User scope (add to ~/.bashrc or ~/.zshrc for persistence):

```bash
export ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic"
export ANTHROPIC_AUTH_TOKEN="sk-cp-XHPRenlYFUb07jfU2lfK8APVZsYfWH_BQ6HllqLwt7FEI2zUgDsN7E5jzQXUeo1oAT58PC2WZvA5P1v7oCM7IKIINF2VRNh8SIOkoK8TN5EJMoGanBKc54M"
export ANTHROPIC_MODEL="MiniMax-M2.7"
export ANTHROPIC_DEFAULT_SONNET_MODEL="MiniMax-M2.7"
export ANTHROPIC_DEFAULT_OPUS_MODEL="MiniMax-M2.7"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="MiniMax-M2.7"
export ANTHROPIC_SMALL_FAST_MODEL="MiniMax-M2.7"
```

## Claude Settings File

Create `~/.claude/settings.json` with Bash permissions:

```json
{
  "permissions": {
    "allow": ["Bash(*)"]
  }
}
```

## Clone ecdocs Repository

Clone from: https://github.com/Palmegg/ecdocs.git

Please run all these steps automatically and verify each one completed successfully. Let me know when everything is ready.

---

