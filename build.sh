#!/bin/bash
set -e

ELECTRON_VERSION=7.1.10
NOTION_BINARY=notion.exe
NOTION_DMG=notion.dmg

if [[ $1 != windows && $1 != mac ]]; then
  echo Please specify whether you would like to build a DEB package using \
    Windows or macOS sources
  echo Example: ./build.sh windows
  exit 1
fi

# Check for Notion Windows installer
if [ "$1" == windows ] && ! [ -f $NOTION_BINARY ]; then
  echo Notion installer missing!
  echo Please download Notion for Windows from https://www.notion.so/desktop \
    and place the installer in this directory as $NOTION_BINARY
  exit 1
fi

# Check for Notion macOS installer
if [ "$1" == mac ] && ! [ -f $NOTION_DMG ]; then
  echo Notion installer missing!
  echo Please download Notion for macOS from https://www.notion.so/desktop \
    and place the installer in this directory as $NOTION_DMG
  exit 1
fi

# Check for required commands
check-command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo Missing command: "$1"
    exit 1
  fi
}

commands=(
  node npm asar electron-packager electron-installer-debian
  7z convert fakeroot dpkg
)

for command in "${commands[@]}"; do
  check-command "$command"
done

# Check for correct Node version
if ! node --version | grep -q 'v12\.'; then
  echo Incorrect Node version: expected version 12
fi

# Setup the build directory
mkdir -p build

if [ "$1" == windows ]; then
  # Extract the Notion executable
  if ! [ -f "build/notion/\$PLUGINSDIR/app-64.7z" ]; then
    7z x $NOTION_BINARY -obuild/notion
  fi

  # Extract the app bundle
  if ! [ -f build/bundle/resources/app.asar ]; then
    7z x "build/notion/\$PLUGINSDIR/app-64.7z" -obuild/bundle
  fi

  # Extract the app container
  if ! [ -d build/app ]; then
    asar extract build/bundle/resources/app.asar build/app
  fi
elif [ "$1" == mac ]; then
  # Extract the Notion disk image
  if ! [ -f 'build/notion/Notion Installer/Notion.app/Contents/Resources/app.asar' ]; then
    7z x $NOTION_DMG -obuild/notion
  fi

  if ! [ -d build/app ]; then
    asar extract \
      'build/notion/Notion Installer/Notion.app/Contents/Resources/app.asar' \
      build/app
  fi
fi

# Install NPM dependencies
if ! [ -f build/app/package-lock.json ]; then
  rm -rf build/app/node_modules
  npm install --prefix build/app
fi

# Convert icon.ico to PNG
if ! [ -f build/app/icon.png ]; then
  convert 'build/app/icon.ico[0]' build/app/icon.png
fi

# Create Electron distribution
if ! [ -d build/dist ]; then
  electron-packager build/app app \
    --platform linux \
    --arch x64 \
    --out build/dist \
    --electron-version $ELECTRON_VERSION \
    --executable-name Notion
fi

# Create Debian package
electron-installer-debian \
  --src build/dist/app-linux-x64 \
  --dest out \
  --arch amd64 \
  --options.icon build/dist/app-linux-x64/resources/app/icon.png
