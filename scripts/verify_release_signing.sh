#!/bin/bash
set -euo pipefail

allow_ad_hoc=false
if [[ ${1:-} == --allow-ad-hoc ]]; then
    allow_ad_hoc=true
    shift
fi
app_path=${1:?Usage: verify_release_signing.sh [--allow-ad-hoc] /path/to/LibreShot.app}
codesign --verify --deep --strict "$app_path"
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
