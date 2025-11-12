#!/bin/bash

echo "=== 256-COLOR TEST ==="
echo ""

echo "Test 1: System colors (0-15)"
for i in {0..15}; do
    printf "\033[38;5;${i}m%3d\033[0m " $i
    if [ $(($i % 8)) -eq 7 ]; then echo ""; fi
done
echo ""

echo "Test 2: RGB 6x6x6 cube samples (16-231)"
echo "Reds (shades of red):"
for i in 16 52 88 124 160 196; do
    printf "\033[38;5;${i}m▀▀▀\033[0m "
done
echo ""

echo "Greens (shades of green):"
for i in 22 28 34 40 46 82; do
    printf "\033[38;5;${i}m▀▀▀\033[0m "
done
echo ""

echo "Blues (shades of blue):"
for i in 17 18 19 20 21 57; do
    printf "\033[38;5;${i}m▀▀▀\033[0m "
done
echo ""

echo "Test 3: Grayscale ramp (232-255)"
for i in {232..255}; do
    printf "\033[38;5;${i}m▀"
done
printf "\033[0m\n"

echo ""
echo "Test 4: Background colors (48;5;n)"
echo -en "\033[48;5;196mRed BG\033[0m "
echo -en "\033[48;5;46mGreen BG\033[0m "
echo -en "\033[48;5;21mBlue BG\033[0m "
echo -en "\033[48;5;226mYellow BG\033[0m "
echo -en "\033[48;5;201mMagenta BG\033[0m "
echo ""

echo ""
echo "Test 5: Full color palette"
# Show color cube
for g in {0..5}; do
    for r in {0..5}; do
        for b in {0..5}; do
            color=$((16 + r*36 + g*6 + b))
            printf "\033[38;5;${color}m▀"
        done
        printf " "
    done
    printf "\033[0m\n"
done

echo ""
echo "If you see:"
echo "✓ 16 system colors"
echo "✓ Various shades of red, green, blue"
echo "✓ Smooth grayscale gradient"
echo "✓ Colored backgrounds"
echo "✓ Rainbow-like color cube"
echo "Then 256-color support is working!"