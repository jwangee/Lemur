#!/bin/bash
# This script installs Python and pip by using a Python version
# management tool, i.e. pyenv (https://github.com/pyenv/pyenv).
# Note: pyenv may affect your current Python dependency.

# Install Ubuntu tools
sudo apt update
sudo apt install -y libreadline-dev

# Install pyenv
git clone https://github.com/pyenv/pyenv.git ~/.pyenv
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bash_profile
echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bash_profile
echo -e 'if command -v pyenv 1>/dev/null 2>&1; then\n  eval "$(pyenv init -)"\nfi' >> ~/.bash_profile
source ~/.bash_profile

# Check pyenv
pyenv versions

# Install Python + pip
pyenv install 2.7.15
pyenv local 2.7.15

which python
which pip
