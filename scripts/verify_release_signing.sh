#!/bin/bash
set -euo pipefail

allow_ad_hoc=false
if [[ ${1:-} == --allow-ad-hoc ]]; then
    allow_ad_hoc=true
    shift
fi
app_path=${1:?Usage: verify_release_signing.sh [--allow-ad-hoc] /path/to/LibreShot.app}
codesign --verify --deep --strict "$app_path"
worker_path="$app_path/Contents/MacOS/LibreShotOCRWorker"
[[ -x "$worker_path" ]] || { echo 'Missing OCR worker' >&2; exit 1; }
python3 - "$app_path" "$worker_path" <<'PYVERIFY'
import plistlib, subprocess, sys
app,worker=sys.argv[1:]
info=plistlib.loads(subprocess.check_output(['plutil','-convert','xml1','-o','-',app+'/Contents/Info.plist']))
parent_arch=set(subprocess.check_output(['lipo','-archs',app+'/Contents/MacOS/'+info['CFBundleExecutable']],text=True).split())
worker_arch=set(subprocess.check_output(['lipo','-archs',worker],text=True).split())
assert parent_arch==worker_arch, 'OCR worker architecture mismatch'
entitlements=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',worker],stderr=subprocess.DEVNULL))
assert entitlements=={'com.apple.security.app-sandbox': True,'com.apple.security.inherit': True}, 'Unexpected OCR worker sandbox entitlements'
def signature(path):
    output=subprocess.run(['codesign','-dv','--verbose=4',path],capture_output=True,text=True,check=True).stderr
    return [line for line in output.splitlines() if line.startswith(('Authority=','TeamIdentifier=','Signature='))]
assert signature(app)==signature(worker), 'OCR worker signing identity mismatch'
PYVERIFY
signature=$(codesign -dv --verbose=4 "$app_path" 2>&1)
if grep -q '^Authority=Developer ID Application:' <<< "$signature" &&
   grep -Eq '^TeamIdentifier=[A-Z0-9]{10}$' <<< "$signature"; then
    exit 0
fi
if $allow_ad_hoc && grep -q '^Signature=adhoc$' <<< "$signature" &&
   grep -q '^TeamIdentifier=not set$' <<< "$signature"; then
    printf 'Ad-hoc signature accepted. Each changed build has a new code identity; screen-recording and input-monitoring permissions may need to be granted again. This package is not notarized.\n' >&2
    exit 0
fi
printf 'Expected a Developer ID Application signature. To intentionally package an ad-hoc build, pass --allow-ad-hoc; development signatures are not accepted for public packages.\n' >&2
exit 1
