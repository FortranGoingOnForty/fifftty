#!/bin/bash
# Test truecolor (24-bit RGB) support

echo "Testing 24-bit truecolor support..."
echo ""

# Test 1: RGB gradient - Red
echo "Red gradient:"
for i in {0..255..5}; do
    printf "\x1b[38;2;${i};0;0m█"
done
printf "\x1b[0m\n"

# Test 2: RGB gradient - Green
echo "Green gradient:"
for i in {0..255..5}; do
    printf "\x1b[38;2;0;${i};0m█"
done
printf "\x1b[0m\n"

# Test 3: RGB gradient - Blue
echo "Blue gradient:"
for i in {0..255..5}; do
    printf "\x1b[38;2;0;0;${i}m█"
done
printf "\x1b[0m\n"

# Test 4: Background colors
echo "Background truecolor:"
for i in {0..255..10}; do
    printf "\x1b[48;2;${i};$((255-i));128m "
done
printf "\x1b[0m\n"

# Test 5: Specific RGB values
echo ""
echo "Specific colors:"
printf "\x1b[38;2;255;100;50mOrange text\x1b[0m "
printf "\x1b[38;2;128;0;128mPurple text\x1b[0m "
printf "\x1b[38;2;0;200;200mCyan text\x1b[0m\n"

# Test 6: Combined foreground and background
printf "\x1b[38;2;255;255;0m\x1b[48;2;128;0;128mYellow on Purple\x1b[0m\n"

echo ""
echo "If you see smooth color gradients, truecolor is working!"
