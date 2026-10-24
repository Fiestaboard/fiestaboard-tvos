#!/usr/bin/env bash
# Run only on an ephemeral macOS release runner. Never enable shell tracing.
set -euo pipefail
umask 077
SIGNING_DIR="$RUNNER_TEMP/app-store-signing"
mkdir -p "$SIGNING_DIR"
export SIGNING_DIR
python3 - <<'PY'
import base64, os, plistlib
from pathlib import Path
p = Path(os.environ['SIGNING_DIR'])
for env, filename in [('APPLE_DISTRIBUTION_P12_BASE64','distribution.p12'),
                      ('APPLE_APP_PROFILE_BASE64','app.mobileprovision'),
                      ('APPLE_TOPSHELF_PROFILE_BASE64','topshelf.mobileprovision')]:
    (p / filename).write_bytes(base64.b64decode(os.environ[env], validate=True))
(p / 'AuthKey.p8').write_text(os.environ['ASC_KEY_P8'])
PY
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
echo "::add-mask::$KEYCHAIN_PASSWORD"
KEYCHAIN_PATH="$SIGNING_DIR/release.keychain-db"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$SIGNING_DIR/distribution.p12" -P "$APPLE_DISTRIBUTION_P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH"
for name in app topshelf; do
  security cms -D -i "$SIGNING_DIR/$name.mobileprovision" > "$SIGNING_DIR/$name.plist"
done
python3 - <<'PY'
import datetime, os, plistlib
from pathlib import Path
p = Path(os.environ['SIGNING_DIR'])
team = os.environ['APPLE_TEAM_ID']
profiles = {}
installed = []
for name, bundle in [('app','com.fiestaboard.tv'),('topshelf','com.fiestaboard.tv.topshelf')]:
    data = plistlib.loads((p / (name + '.plist')).read_bytes())
    ent = data['Entitlements']
    assert ent['application-identifier'] == team + '.' + bundle, 'Wrong profile bundle/team'
    assert 'group.com.fiestaboard.tv' in ent.get('com.apple.security.application-groups', []), 'Missing App Group'
    assert ent.get('get-task-allow') is False, 'Development profile cannot be released'
    assert 'tvOS' in data.get('Platform', []), 'Wrong platform'
    assert data['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Expired profile'
    assert not data.get('ProvisionedDevices') and not data.get('ProvisionsAllDevices'), 'Not an App Store profile'
    profiles[bundle] = data['Name']
    for directory in (Path.home()/'Library/MobileDevice/Provisioning Profiles',
                      Path.home()/'Library/Developer/Xcode/UserData/Provisioning Profiles'):
        directory.mkdir(parents=True, exist_ok=True)
        dest = directory / (data['UUID'] + '.mobileprovision')
        dest.write_bytes((p / (name + '.mobileprovision')).read_bytes())
        installed.append(str(dest))
(p/'installed-profiles.txt').write_text('\n'.join(installed)+'\n')
(p/'profiles.json').write_text(__import__('json').dumps(profiles))
with (p/'ExportOptions.plist').open('wb') as out:
    plistlib.dump({'method':'app-store-connect','destination':'export','signingStyle':'manual',
                  'teamID':team,'signingCertificate':'Apple Distribution','provisioningProfiles':profiles,
                  'manageAppVersionAndBuildNumber':False,'uploadSymbols':True,
                  'testFlightInternalTestingOnly':False},out)
PY
ruby -rxcodeproj -rjson -e '
  profiles = JSON.parse(File.read(File.join(ENV.fetch("SIGNING_DIR"), "profiles.json")))
  project = Xcodeproj::Project.open("FiestaBoardTV.xcodeproj")
  project.targets.each do |target|
    target.build_configurations.each do |config|
      bundle = config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"]
      next unless profiles.key?(bundle)
      config.build_settings["DEVELOPMENT_TEAM"] = ENV.fetch("APPLE_TEAM_ID")
      config.build_settings["CODE_SIGN_STYLE"] = "Manual"
      config.build_settings["CODE_SIGN_IDENTITY"] = "Apple Distribution"
      config.build_settings["PROVISIONING_PROFILE_SPECIFIER"] = profiles.fetch(bundle)
    end
  end
  project.save
'
