# LibreChat - Simple Setup

> **One-Command Setup**: Get LibreChat running in minutes, not hours.

## 🚀 Quick Start

1. **Get your API key** from your provider
2. **Run the setup**:
   ```bash
   ./run.bash
   ```
3. **Open LibreChat** at [http://localhost:3080](http://localhost:3080)

That's it! The script handles everything else automatically.

## 💡 The KISS Philosophy

This setup follows the **"Keep It Simple, Stupid"** principle:

### ✅ What We Made Simple
- **No manual configuration** - Script detects what you need
- **No environment file editing** - Interactive prompts handle everything
- **No complex networking** - Everything runs on your computer
- **No security worries** - Passwords are hardcoded (containers aren't exposed)
- **No data loss** - Everything stored in `./data/` folder for easy backup

### 🧠 Smart Configuration Discovery

Instead of maintaining complex configuration files, we built a smart system:

```mermaid
flowchart TD
    A[Run Script] --> B[Scan docker-compose.yml]
    A --> C[Scan librechat.yml]
    B --> D[Find ${VARIABLES}]
    C --> D
    D --> E[Check .env file]
    E --> F{Missing variables?}
    F -->|Yes| G[Prompt user interactively]
    F -->|No| H[Generate security keys]
    G --> H
    H --> I[Start LibreChat]
```

**The magic**: When you add MCP servers or other features to `librechat.yml`, the script automatically discovers any `${VARIABLES}` you use and prompts you to configure them. No manual maintenance required!

## 🛠 What The Script Does For You

### Automatic Setup
- ✅ **Creates data directories** - For your chats, uploads, and database
- ✅ **Generates security keys** - JWT tokens, encryption keys (64-character secure random)
- ✅ **Validates configuration** - Ensures all required variables are set
- ✅ **Starts services** - Docker containers with proper dependencies
- ✅ **Creates admin user** - Prompts you to set up your first account

### Smart Detection
- 🔍 **Scans your config files** - Finds all `${VARIABLE}` references automatically
- 🤖 **Prompts for missing values** - No need to edit files manually
- 🔐 **Handles secrets intelligently** - Auto-generates what it can, asks for what it can't
- 📁 **Organizes everything** - All your data in one easy-to-backup folder

## 📂 Project Structure

```
librechat/
├── run.bash              # 🚀 One-command setup script
├── docker-compose.yml    # 🐳 Service definitions (hardcoded defaults)
├── librechat.yml         # ⚙️  LibreChat configuration (your custom settings)
├── .env.example          # 📋 Template for environment variables
├── .env                  # 🔑 Your actual API keys (created by script)
└── data/                 # 💾 All your data (easy to backup)
    ├── mongodb/          #    Database files
    ├── uploads/          #    File uploads
    ├── images/           #    User images
    └── logs/             #    Application logs
```

## 🔧 How It Works

### The Smart Parts

1. **Configuration Discovery**: The script reads `docker-compose.yml` and `librechat.yml` to find all `${VARIABLE}` references automatically.

2. **Minimal User Input**: You only need to provide your API key. Everything else is either auto-generated or has sensible defaults.

3. **Extensible Design**: Add MCP servers to `librechat.yml`? The script automatically detects new variables and prompts for them.

### The Simple Parts

- **Hardcoded Infrastructure**: Database passwords, ports, service names are fixed (containers aren't exposed anyway)
- **Data Folder**: Everything important goes in `./data/` - easy to backup your entire LibreChat
- **One Entry Point**: `./run.bash` does everything - setup, start, user creation

## 🔐 Security Made Simple

- **Auto-generated secrets**: JWT tokens and encryption keys are created with proper entropy
- **Hardcoded database passwords**: Since containers run locally and aren't exposed
- **No exposed ports**: Only LibreChat (port 3080) is accessible from outside Docker
- **Secure by default**: Authentication enabled, registration disabled by default

## 🔌 Adding MCP Servers

When you want to add MCP (Model Context Protocol) servers:

1. **Edit `librechat.yml`** - Add your MCP server configuration:
   ```yaml
   mcpServers:
     github:
       command: "npx"
       args: ["-y", "@modelcontextprotocol/server-github"]
       env:
         GITHUB_PERSONAL_ACCESS_TOKEN: ${MCP_SERVER_GITHUB_TOKEN}
   ```

2. **Run the script again** - It automatically detects the new variable:
   ```bash
   ./run.bash
   ```

3. **Enter your token** - When prompted:
   ```
   Enter value for MCP_SERVER_GITHUB_TOKEN: ghp_your_token_here
   ```

That's it! No need to edit `.env.example` or any other files.

## 🚨 Troubleshooting

### Common Issues

**"Command not found: docker"**
- Install Docker Desktop from [docker.com](https://docker.com)

**"Permission denied: ./run.bash"**
```bash
chmod +x run.bash
```

**"API key required"**
- Get your API key from your provider
- The script will prompt you to enter it

**"Port 3080 already in use"**
- Stop other LibreChat instances: `docker-compose down`
- Or change the port in `docker-compose.yml`

### Getting Help

- **View logs**: `docker logs LibreChat-API -f`
- **Stop services**: `docker-compose down`
- **Restart services**: `docker-compose restart`
- **Reset everything**: Delete `./data/` folder and run `./run.bash` again

## 🎯 Why This Approach?

### Traditional Setup Problems
- ❌ Complex environment files with dozens of variables
- ❌ Manual secret generation with unclear requirements
- ❌ Database setup with authentication configuration
- ❌ Port conflicts and networking issues
- ❌ Forgetting to create admin users
- ❌ Configuration drift when adding new features

### Our Solution
- ✅ **One command setup** - `./run.bash` handles everything
- ✅ **Smart configuration** - Automatically discovers what you need
- ✅ **Secure defaults** - Auto-generates proper secrets
- ✅ **Easy backup** - All data in one `./data/` folder
- ✅ **Extensible** - Adding MCP servers is automatic
- ✅ **User-friendly** - Clear prompts and error messages

## 🌟 The Result

You get a LibreChat installation that:
- **Just works** out of the box
- **Stays secure** with proper secret management
- **Grows with you** as you add MCP servers and features
- **Is easy to backup** with a single folder
- **Can be understood** by both technical and non-technical users

---

*Made with ❤️ for the LibreChat community. Because AI chat should be simple to set up.*