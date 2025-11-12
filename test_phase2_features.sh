#!/bin/bash

echo "=== PHASE 2 FEATURE TESTS ==="
echo ""

echo "Test 1: Bold text (should appear brighter)"
echo -e "\033[1mThis text is bold\033[0m"
echo -e "Normal: \033[31mRed\033[0m vs Bold: \033[1;31mBold Red\033[0m"
echo ""

echo "Test 2: Underline text"
echo -e "\033[4mThis text is underlined\033[0m"
echo -e "\033[4;32mGreen underlined text\033[0m"
echo ""

echo "Test 3: Bold + Underline combined"
echo -e "\033[1;4mBold and underlined text\033[0m"
echo -e "\033[1;4;34mBlue bold underlined\033[0m"
echo ""

echo "Test 4: Arrow keys (try pressing Up to recall this command)"
echo "Press Up arrow to test command history"
echo ""

echo "Test 5: All 16 colors with bold variants"
for i in {0..7}; do
    echo -en "\033[3${i}m▀\033[0m"  # Normal color
    echo -en "\033[1;3${i}m▀\033[0m"  # Bold (bright) color
done
echo ""

echo "Test 6: Cursor movement sequences (no stray text should appear)"
echo -en "Testing cursor\033[5D"  # Move left 5
echo -en "\033[3C"  # Move right 3
echo " movement"
echo ""

echo "Test completed! Check for:"
echo "✓ Bold text appears brighter"
echo "✓ Underlines are visible"
echo "✓ Arrow keys work without stray characters"
echo "✓ All 16 colors display correctly"