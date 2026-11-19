#!/bin/zsh
# Construit « mPARLE.app » (ou « mPARLE DEV.app » avec DEV=1), la signe (certificat local stable) puis installe la version
# normale dans ~/Applications/Applications Personnelles. NO_INSTALL=1 : ne pas installer ; NO_OPEN=1 : ne pas lancer.
set -euo pipefail
cd "$(dirname "$0")"
if [ -n "${DEV:-}" ]; then NAME="mPARLE DEV"; ID="fr.stephan.mparle.dev"; else NAME="mPARLE"; ID="fr.stephan.mparle"; fi
APP="$NAME.app"
DEST="$HOME/Applications/Applications Personnelles"
rm -rf "${APP:?}" build; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 -o "$APP/Contents/MacOS/mPARLE" Sources/*.swift

[ -f assets/AppIcon.icns ] && cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Titre du Service « Traduire avec mPARLE » dans les 4 langues
for l in fr en es it; do mkdir -p "$APP/Contents/Resources/$l.lproj"; cp "Resources/$l.lproj/InfoPlist.strings" "$APP/Contents/Resources/$l.lproj/InfoPlist.strings"; done
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ID" -c "Set :CFBundleDisplayName $NAME" -c "Set :CFBundleName $NAME" "$APP/Contents/Info.plist"
if [ -n "${DEV:-}" ]; then /usr/libexec/PlistBuddy -c "Set :NSServices:0:NSMenuItem:default 'Traduire avec mPARLE DEV'" -c "Set :NSServices:0:NSPortName 'mPARLE DEV'" "$APP/Contents/Info.plist"; fi
rm -rf build

SIGN="/Volumes/SKYRIM/TOOLS/MAC/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then "$SIGN" "$APP"; else codesign --force --deep -s - "$APP"; fi

if [ -z "${DEV:-}" ] && [ -z "${NO_INSTALL:-}" ]; then
  mkdir -p "$DEST"
  pkill -x mPARLE 2>/dev/null || true
  rm -rf "${DEST:?}/${APP:?}"; cp -R "$APP" "$DEST/$APP"
  echo "Installée : $DEST/$APP"
fi
echo "OK : $APP"
