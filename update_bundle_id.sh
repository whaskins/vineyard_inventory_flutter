#!/bin/bash

# Path to Info.plist
INFO_PLIST="ios/Runner/Info.plist"

# New bundle identifier
NEW_BUNDLE_ID="com.vineyard.inventory"

# Update the CFBundleIdentifier in Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleName Vineyard Inventory" "$INFO_PLIST"

echo "Updated bundle ID to $NEW_BUNDLE_ID"