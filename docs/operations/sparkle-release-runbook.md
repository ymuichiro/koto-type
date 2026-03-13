# Sparkle Release Runbook

## 1. Goal
- Ship every release with three artifacts: `.dmg`, update `.zip`, and `appcast.xml`.
- Ensure appcast + update archive signatures are valid before publishing.

## 2. Key Management

### 2.1 Generate keys (one-time)
```bash
./scripts/fetch_sparkle_tools.sh 2.9.0 build/sparkle-tools
build/sparkle-tools/bin/generate_keys --account "<team-or-project-account>"
```

`generate_keys` prints the public key. Set it as:
- GitHub Actions secret: `SPARKLE_PUBLIC_ED_KEY`
- Build-time env: `KOTOTYPE_SPARKLE_PUBLIC_ED_KEY`

### 2.2 Export private key for CI (secure channel only)
```bash
build/sparkle-tools/bin/generate_keys --account "<team-or-project-account>" -x /secure/path/sparkle_private.key
```

Store the file content in GitHub Actions secret:
- `SPARKLE_PRIVATE_ED_KEY`

Rules:
- Never commit private keys.
- Keep encrypted backups.
- Restrict who can read/update CI secrets.

## 3. Local Validation Flow

```bash
make build-server
cd KotoType
swift build -c release
KOTOTYPE_BUILD_CONFIG=release \
KOTOTYPE_SPARKLE_PUBLIC_ED_KEY="<public-key>" \
KOTOTYPE_SPARKLE_FEED_URL="http://127.0.0.1:8000/appcast.xml" \
./scripts/create_app.sh
./scripts/create_update_zip.sh
KOTOTYPE_SPARKLE_PRIVATE_ED_KEY="$(cat /secure/path/sparkle_private.key)" \
KOTOTYPE_SPARKLE_DOWNLOAD_URL_PREFIX="http://127.0.0.1:8000/" \
GENERATE_APPCAST_BIN="../build/sparkle-tools/bin/generate_appcast" \
SIGN_UPDATE_BIN="../build/sparkle-tools/bin/sign_update" \
./scripts/generate_appcast.sh
./scripts/create_dmg.sh
```

## 4. Local Distribution Smoke Test

```bash
cd KotoType
python3 -m http.server 8000
```

In another terminal:
```bash
curl -fsS http://127.0.0.1:8000/appcast.xml > /tmp/kototype-appcast.xml
curl -I -fsS http://127.0.0.1:8000/KotoType-$(./scripts/version.sh).zip
```

## 5. Signature Verification

```bash
cd KotoType
../build/sparkle-tools/bin/sign_update --verify \
  --ed-key-file /secure/path/sparkle_private.key \
  appcast.xml
```

Then verify enclosure signature from `appcast.xml` against update zip:
```bash
ZIP_SIGNATURE="$(python3 - <<'PY'
import xml.etree.ElementTree as ET
root = ET.parse('appcast.xml').getroot()
for node in root.iter():
    if node.tag.endswith('enclosure'):
        for k, v in node.attrib.items():
            if k.endswith('edSignature'):
                print(v)
                raise SystemExit(0)
raise SystemExit(1)
PY
)"
../build/sparkle-tools/bin/sign_update --verify \
  --ed-key-file /secure/path/sparkle_private.key \
  "KotoType-$(./scripts/version.sh).zip" \
  "${ZIP_SIGNATURE}"
```

## 6. CI/Release Notes
- `.github/workflows/release.yml` already enforces required secrets.
- The workflow now publishes `.dmg`, `.zip`, and `appcast.xml`.
- Release is invalid if `appcast.xml` is not regenerated.
