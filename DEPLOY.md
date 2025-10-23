# How to Deploy This macOS Application

This document provides a step-by-step guide to setting up an automated build, sign, notarize, and release process for the Bridger macOS application using GitHub Actions.

The goal is to automatically create a new release with a downloadable `.dmg` file every time code is pushed to the `main` branch.

## Step 1: Certificates and Secrets (The Annoying Part)

To distribute a macOS app outside the App Store, it must be signed with a Developer ID certificate and notarized by Apple. This ensures users that the app is from a known developer and hasn't been tampered with. We need to provide these credentials securely to the GitHub Actions runner.

### 1.1. Create an App-Specific Password

This password allows the GitHub Actions runner to authenticate with Apple's notarization service on your behalf.

1.  Navigate to [appleid.apple.com](https://appleid.apple.com).
2.  Sign in with your Apple ID.
3.  Go to the **Sign-In and Security** section.
4.  Click on **App-Specific Passwords**.
5.  Click "Generate an app-specific password".
6.  Give it a descriptive label, like `GitHub Actions Notarization`.
7.  Copy the generated password immediately. **You will not see it again.**

### 1.2. Export Your Signing Certificate

You need to export your `Developer ID Application` certificate from your Mac so it can be used on the GitHub runner.

1.  Open the **Keychain Access** app on your Mac.
2.  In the top-left pane, select the **login** keychain. In the bottom-left pane, select the **My Certificates** category.
3.  Find your `Developer ID Application: Your Name (TEAM_ID)` certificate. **Do not use a `Mac Development` or `Apple Development` certificate.**
4.  Right-click on the certificate and choose **Export...**.
5.  Save it as a `.p12` file.
6.  You will be prompted to create a password to protect the exported file. **Remember this password.**

### 1.3. Add Secrets to Your GitHub Repository

Navigate to your GitHub repository -> **Settings** -> **Secrets and variables** -> **Actions**. Create the following repository secrets:

*   `APPLE_ID`: Your Apple ID email address.
*   `APP_SPECIFIC_PASSWORD`: The app-specific password you generated in step 1.1.
*   `SIGNING_CERTIFICATE_PASSWORD`: The password you created for the `.p12` certificate file in step 1.2.
*   `SIGNING_CERTIFICATE_BASE64`: The base64-encoded version of your `.p12` certificate. To generate this, run the following command in your terminal:
    ```bash
    base64 -i /path/to/your/certificate.p12
    ```
    Copy the entire output and paste it as the value for this secret.

## Step 2: Create `ExportOptions.plist`

This file tells Xcode how to export the archived app, specifying the signing method and your team details.

Create a file named `ExportOptions.plist` in the root of your project with the following content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
```

**Important:** Replace `YOUR_TEAM_ID` with your actual Apple Developer Team ID. You can find it on your [Apple Developer Account Membership Details page](https://developer.apple.com/account/#!/membership).

## Step 3: Create the GitHub Actions Workflow

This YAML file defines the entire automated process.

1.  Create a directory named `.github` in your project root if it doesn't exist.
2.  Inside `.github`, create another directory named `workflows`.
3.  Inside `workflows`, create a file named `release.yml`.

Paste the following content into `release.yml`:

```yaml
name: Build and Release macOS App

on:
  push:
    branches:
      - main # Trigger on push to the main branch

jobs:
  build:
    runs-on: macos-latest # The job must run on a macOS virtual machine

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install certificate
        uses: apple-actions/import-codesign-cert@v3
        with:
          p12-file-base64: ${{ secrets.SIGNING_CERTIFICATE_BASE64 }}
          p12-password: ${{ secrets.SIGNING_CERTIFICATE_PASSWORD }}

      - name: Build and archive
        run: |
          xcodebuild -project bridge.xcodeproj \
                     -scheme bridge \
                     -configuration Release \
                     -archivePath $RUNNER_TEMP/bridge.xcarchive \
                     archive

      - name: Export app
        run: |
          xcodebuild -exportArchive \
                     -archivePath $RUNNER_TEMP/bridge.xcarchive \
                     -exportPath $RUNNER_TEMP/build \
                     -exportOptionsPlist ExportOptions.plist

      - name: Notarize app (Upload)
        run: |
          # Create a zip file, as required by the notarization tool
          ditto -c -k --sequesterRsrc --keepParent $RUNNER_TEMP/build/bridge.app $RUNNER_TEMP/bridge.zip
          
          # Submit the app to Apple for notarization
          xcrun altool --notarize-app \
                      --primary-bundle-id "YOUR_BUNDLE_ID" \
                      --username "${{ secrets.APPLE_ID }}" \
                      --password "${{ secrets.APP_SPECIFIC_PASSWORD }}" \
                      --file $RUNNER_TEMP/bridge.zip
        # IMPORTANT: Replace YOUR_BUNDLE_ID with your app's actual Bundle Identifier

      - name: Create DMG for Release
        run: |
          hdiutil create -volname "Bridger" \
                         -srcfolder "$RUNNER_TEMP/build/bridge.app" \
                         -ov -format UDZO \
                         "$RUNNER_TEMP/Bridger.dmg"

      - name: Create Release Tag
        id: tag
        run: echo "tag_name=$(date +'%Y-%m-%d-%H-%M-%S')" >> $GITHUB_ENV

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: "$RUNNER_TEMP/Bridger.dmg" # Attach the DMG to the release
          tag_name: ${{ env.tag_name }}
          name: "Release ${{ env.tag_name }}"
          body: "Automated release of Bridger for macOS."
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Important:** In the `Notarize app` step, replace `YOUR_BUNDLE_ID` with your application's actual Bundle ID (e.g., `com.yourcompany.bridge`).

## Result

Once these files are in place and the secrets are configured, every push to the `main` branch will trigger the workflow. It will build, sign, and notarize the application, and finally, it will create a new release on your GitHub repository's "Releases" page with a user-friendly `.dmg` file attached.
