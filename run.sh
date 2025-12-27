#!/bin/bash
cd "$(dirname "$0")"

VENV_DIR=".venv"
PYTHON_CMD="python3"
REQUIREMENTS_FILE="src/requirements.txt"

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

echo "Starting FnMacAssistant..."
python FnMacAssistant.py || error_exit
