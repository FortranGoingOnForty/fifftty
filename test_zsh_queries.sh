#!/bin/bash

# Test script to check zsh query behavior
echo "Testing zsh escape sequence queries..."
echo ""
echo "Starting fortty with debug output..."
echo "Type 'echo test' and press Enter, then type 'exit' to quit"
echo ""

# Run fortty and capture all debug output
./build/fortty 2>&1 | tee fortty_debug.log &
FORTTY_PID=$!

# Give it time to start
sleep 2

# Kill after timeout
sleep 30 && kill $FORTTY_PID 2>/dev/null &

wait $FORTTY_PID

echo ""
echo "Checking for query sequences in debug log..."
grep -E "CSI.*6.*n|CSI.*c[^a-z]|DA request|cursor position" fortty_debug.log || echo "No cursor position or DA queries found!"
echo ""
echo "Checking what sequences were sent..."
grep "DEBUG:" fortty_debug.log | head -20