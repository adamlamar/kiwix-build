#!/bin/bash

# Generate MSIX logo assets from SVG
# Usage: ./generate-logos.sh [svg-file]

SVG_FILE="${1:-kiwix-logo.svg}"
SQUARE_SVG_FILE="${2:-kiwix-app-icons-square.svg}"

if [ ! -f "$SVG_FILE" ]; then
    echo "Error: SVG file '$SVG_FILE' not found!"
    echo "Usage: $0 [svg-file] [square-svg-file]"
    exit 1
fi

if [ ! -f "$SQUARE_SVG_FILE" ]; then
    echo "Error: Square SVG file '$SQUARE_SVG_FILE' not found!"
    echo "Usage: $0 [svg-file] [square-svg-file]"
    exit 1
fi

echo "Generating MSIX logo assets from: $SVG_FILE (wide) and $SQUARE_SVG_FILE (square)"

# Check if Inkscape is installed
if ! command -v inkscape &> /dev/null; then
    echo "Error: Inkscape not found. Install with: sudo apt install inkscape"
    exit 1
fi

echo "Using Inkscape for SVG rendering"

# Generate all required MSIX logo sizes
echo "Creating Square44x44Logo.png (44x44px) from square SVG..."
inkscape "$SQUARE_SVG_FILE" --export-filename=Square44x44Logo.png --export-width=44 --export-height=44

echo "Creating Square150x150Logo.png (150x150px) from square SVG..."
inkscape "$SQUARE_SVG_FILE" --export-filename=Square150x150Logo.png --export-width=150 --export-height=150

echo "Creating Wide310x150Logo.png (310x150px) from wide SVG..."
inkscape "$SVG_FILE" --export-filename=Wide310x150Logo.png --export-width=310 --export-height=150

echo "Creating StoreLogo.png (50x50px) from square SVG..."
inkscape "$SQUARE_SVG_FILE" --export-filename=StoreLogo.png --export-width=50 --export-height=50

echo ""
echo "✅ All logo assets generated successfully!"
echo ""
echo "Generated files:"
ls -la *.png | grep -E "(Square|Wide|Store)" | while read line; do
    echo "  $line"
done

echo ""
echo "Files are ready for MSIX packaging!"
