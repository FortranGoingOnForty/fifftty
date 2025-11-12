#!/bin/bash

echo "Testing arrow key escape sequences..."
echo "Instructions:"
echo "1. Type 'ls'"
echo "2. Press Enter"
echo "3. Press Up arrow to recall command"
echo "4. Look for any stray characters or sequences"
echo "5. Type 'exit' to quit"
echo ""

./build/fortty 2>&1 | tee arrow_test.log