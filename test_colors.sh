#!/bin/bash
# Test script for ANSI color rendering

echo "Testing ANSI colors in fortty:"
echo ""

# Test normal colors (30-37)
echo -e "\033[31mRed text\033[0m"
echo -e "\033[32mGreen text\033[0m"
echo -e "\033[33mYellow text\033[0m"
echo -e "\033[34mBlue text\033[0m"
echo -e "\033[35mMagenta text\033[0m"
echo -e "\033[36mCyan text\033[0m"
echo -e "\033[37mWhite text\033[0m"

echo ""
echo "Bright colors (90-97):"

# Test bright colors (90-97)
echo -e "\033[91mBright Red\033[0m"
echo -e "\033[92mBright Green\033[0m"
echo -e "\033[93mBright Yellow\033[0m"
echo -e "\033[94mBright Blue\033[0m"
echo -e "\033[95mBright Magenta\033[0m"
echo -e "\033[96mBright Cyan\033[0m"
echo -e "\033[97mBright White\033[0m"

echo ""
echo "Attributes:"
echo -e "\033[1mBold text\033[0m"
echo -e "\033[3mItalic text\033[0m"
echo -e "\033[4mUnderlined text\033[0m"

echo ""
echo "Color test complete!"
