# Installation Guide

## Quick Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/clintrorick/repomix-autotune/main/install.sh | bash
```

## Alternative Installation Methods

### Option 1: Git Clone + Manual Install

```bash
git clone https://github.com/clintrorick/repomix-autotune.git
cd repomix-autotune
chmod +x repomix-autotune.sh
sudo cp repomix-autotune.sh /usr/local/bin/repomix-autotune
```

### Option 2: Direct Download

```bash
# Download to /usr/local/bin
sudo curl -fsSL https://raw.githubusercontent.com/clintrorick/repomix-autotune/main/repomix-autotune.sh -o /usr/local/bin/repomix-autotune
sudo chmod +x /usr/local/bin/repomix-autotune
```

### Option 3: Local Installation (No sudo)

```bash
# Install to ~/bin (make sure ~/bin is in your PATH)
mkdir -p ~/bin
curl -fsSL https://raw.githubusercontent.com/clintrorick/repomix-autotune/main/repomix-autotune.sh -o ~/bin/repomix-autotune
chmod +x ~/bin/repomix-autotune
```

### Option 4: Team Distribution via Internal Server

For teams with internal package repositories:

```bash
# Download and host on internal server
wget https://raw.githubusercontent.com/clintrorick/repomix-autotune/main/repomix-autotune.sh
# Then teammates can install from internal URL
curl -fsSL https://your-internal-server.com/tools/repomix-autotune.sh -o /usr/local/bin/repomix-autotune
```

## Prerequisites

Before installing, ensure you have:

1. **repomix**: `npm install -g repomix`
2. **claude CLI**: `curl -fsSL https://claude.ai/install.sh | sh`
3. **jq**: Most systems have this, or install with your package manager
4. **git**: For repository analysis

## Verification

After installation, verify it works:

```bash
repomix-autotune --help
repomix-autotune --version
```

## Team Deployment Strategies

### For Small Teams (< 10 people)
**Recommended**: Share the one-liner install command in Slack/Teams

### For Medium Teams (10-50 people)
**Recommended**: Add to team documentation and onboarding scripts

### For Large Teams/Organizations (50+ people)
**Recommended**: Package in internal tools repository or Homebrew formula

## Updating

To update to the latest version, simply re-run the install command:

```bash
curl -fsSL https://raw.githubusercontent.com/clintrorick/repomix-autotune/main/install.sh | bash
```

## Uninstallation

```bash
sudo rm /usr/local/bin/repomix-autotune
```

## Troubleshooting

### "Permission denied" error
- Run with `sudo` or install to a user directory like `~/bin`

### "Command not found" after installation
- Check that `/usr/local/bin` is in your PATH: `echo $PATH`
- Restart your shell or run `source ~/.bashrc` / `source ~/.zshrc`

### Missing dependencies
- Install missing tools: `brew install jq` (macOS) or `apt install jq` (Ubuntu)