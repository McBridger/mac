#!/bin/bash

# Source configuration variables
if [ -f "./dmg/config.sh" ]; then
    source "./dmg/config.sh"
else
    echo "Error: Configuration file ./dmg/config.sh not found."
    exit 1
fi

# App Build Settings
export APP_SCHEME="McBridger"
export APP_CONFIGURATION="Debug"
export APP_NAME_PREFIX="McBridgerDev"

# --- Build Application ---
echo "Building ${APP_NAME_PREFIX}.app in ${APP_CONFIGURATION} configuration (unsigned)..."

xcodebuild build \
  -scheme "${APP_SCHEME}" \
  -configuration "${APP_CONFIGURATION}" \
  -derivedDataPath "./build/DerivedData" \
  CODE_SIGN_IDENTITY="" \
  PROVISIONING_PROFILE="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO || { echo "Build failed"; exit 1; }

# Find the built .app file directly from DerivedData
BUILT_APP_PATH=$(find ./build/DerivedData -type d -name "*.app" | grep "${APP_CONFIGURATION}" | head -n 1)

if [ -z "${BUILT_APP_PATH}" ]; then
    echo "Error: Could not find the built application in DerivedData. Build failed?"
    exit 1
fi

# Get the actual app bundle name (e.g., McBridgerDev.app)
ACTUAL_APP_NAME=$(basename "${BUILT_APP_PATH}")

echo "Found built application: ${BUILT_APP_PATH}"

# --- Create DMG ---

# Ensure create-dmg is installed
if ! command -v create-dmg &> /dev/null
then
    echo "create-dmg could not be found. Please install it with Homebrew: brew install create-dmg"
    exit 1
fi

echo "Creating DMG: ${DMG_NAME}"

create-dmg \
  --volname "${DMG_VOLNAME}" \
  --background "${DMG_BACKGROUND_IMG}" \
  --window-pos ${DMG_WINDOW_POS} \
  --window-size ${DMG_WINDOW_SIZE} \
  --icon-size ${DMG_ICON_SIZE} \
  --icon "${APP_NAME_PREFIX}.app" ${DMG_APP_ICON_POS} \
  --hide-extension "${APP_NAME_PREFIX}.app" \
  --app-drop-link ${DMG_APP_DROP_LINK_POS} \
  "${DMG_NAME}" \
  "${BUILT_APP_PATH}"

echo "DMG created: ${DMG_NAME}"

# --- Cleanup (optional) ---
# rmdir ./build/DerivedData # Uncomment if you want to clean up DerivedData after DMG creation
