#!/bin/bash

# Configuration
APP_NAME="SwiftDL"
BUNDLE_ID="com.local.swiftdl"
EXECUTABLE_NAME="SwiftDL"

echo "🚀 Building $APP_NAME in Release mode..."
swift build -c release --disable-sandbox

# Create bundle structure
echo "📁 Creating .app bundle structure..."
rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# Copy binary
cp ".build/release/$EXECUTABLE_NAME" "$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "Sources/SwiftDL/Resources/Info.plist" "$APP_NAME.app/Contents/Info.plist"

# Copy AppIcon
cp "Sources/SwiftDL/Resources/AppIcon.icns" "$APP_NAME.app/Contents/Resources/AppIcon.icns"

# Copy other resources (if any)
# Find the resource bundle path if it exists
RESOURCE_BUNDLE=$(find .build/release -name "SwiftDL_SwiftDL.bundle" -type d | head -n 1)
if [ -d "$RESOURCE_BUNDLE" ]; then
    echo "📦 Copying resource bundle..."
    cp -R "$RESOURCE_BUNDLE" "$APP_NAME.app/Contents/Resources/"
fi

# Ensure permissions
chmod +x "$APP_NAME.app/Contents/MacOS/$APP_NAME"

echo "✅ $APP_NAME.app created successfully!"
echo "📍 Path: $(pwd)/$APP_NAME.app"
echo "💡 You can now move this to your /Applications folder."
