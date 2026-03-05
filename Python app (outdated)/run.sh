#!/bin/bash
cd "$(dirname "$0")"

VENV_DIR=".venv"
PYTHON_CMD="python3"
REQUIREMENTS_FILE="src/requirements.txt"

WATCH_MODE=0
if [[ "${1:-}" == "--watch" || "${1:-}" == "-w" ]]; then WATCH_MODE=1; fi

error_exit() {
    rm -rf "$VENV_DIR"

    echo ""
    echo "Error: Initialization failed."
    echo "Please verify your Python installation."
    echo "It is recommended to use Homebrew Python instead of the native macOS Python."
    echo "Try running: brew install python python-tk"
    exit 1
}

# Check if python3 and tkinter is available
if ! "$PYTHON_CMD" -c "import tkinter" &> /dev/null; then
    echo "Error: Tkinter support not found in $PYTHON_CMD."
    error_exit
fi

echo "Using Python: $("$PYTHON_CMD" --version)"

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    "$PYTHON_CMD" -m venv "$VENV_DIR" || error_exit
fi

echo "Checking dependencies..."
source "$VENV_DIR/bin/activate" || error_exit
if [ -f "$REQUIREMENTS_FILE" ]; then
    pip install -r "$REQUIREMENTS_FILE" > /dev/null || error_exit
fi

runApp() {
    autoflake --in-place --remove-all-unused-imports --remove-unused-variables --recursive src FnMacAssistant.py && \
    autopep8 --in-place --recursive --aggressive --aggressive src FnMacAssistant.py && \
    flake8 src --count --show-source --statistics --ignore=E501 && \
    vulture FnMacAssistant.py src --min-confidence 60 && \
    exec python FnMacAssistant.py
}

if [[ "${1:-}" == "--internal-run" ]]; then
    runApp
    exit 0
fi

if [[ "${WATCH_MODE}" -eq 1 ]]; then
    echo "Starting FnMacAssistant in dev mode watching for changes..."
    exec python -m watchfiles --filter python "bash $0 --internal-run" FnMacAssistant.py src
else
    echo "Starting FnMacAssistant..."
    runApp || error_exit
fi
