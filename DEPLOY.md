# Deployment Guide

## GitHub Repository Setup

### Initial Repository Creation

```bash
# Initialize git repository
git init

# Add all files
git add .

# Initial commit
git commit -m "Initial commit: Parachute CFD Landing Game

- Google Earth terrain import pipeline
- OpenFOAM CFD wind simulation setup
- Godot game engine integration
- Wind rotor visualization system
- Complete documentation and examples"

# Create GitHub repository (requires gh CLI)
# Alternative: Create manually at github.com/new
gh repo create parachute-cfd-game --public --source=. --remote=origin --push

# Or if repository already exists on GitHub:
git remote add origin https://github.com/YOUR_USERNAME/parachute-cfd-game.git
git branch -M main
git push -u origin main