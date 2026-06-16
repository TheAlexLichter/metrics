# Check runner compatibility
set -euo pipefail
echo "::group::Metrics native setup"
echo "GitHub action: $METRICS_ACTION ($METRICS_ACTION_PATH)"
cd "$METRICS_ACTION_PATH"
MISSING_DEPENDENCIES=0
for DEPENDENCY in jq node npm; do
  if ! which $DEPENDENCY > /dev/null 2>&1; then
    echo "::error::\"$DEPENDENCY\" is not installed on current runner but is needed to run metrics"
    MISSING_DEPENDENCIES=1
  fi
done
if [[ $MISSING_DEPENDENCIES == "1" ]]; then
  echo "Runner compatibility: missing dependencies"
  exit 1
else
  echo "Runner compatibility: compatible"
fi

# Export action inputs using the same URI encoding expected by metadata.mjs
while IFS= read -r INPUT; do
  export "$INPUT"
done < <(echo "$INPUTS" | jq -r 'to_entries|map("INPUT_\(.key|ascii_upcase)=\(.value|@uri)")|.[]')
echo "Environment variables: loaded"

# Renders output folder
METRICS_RENDERS="/metrics_renders"
sudo mkdir -p $METRICS_RENDERS
sudo chown "$(id -u):$(id -g)" $METRICS_RENDERS
export METRICS_RENDERS
echo "Renders output folder: $METRICS_RENDERS"

# Version (picked from package.json)
METRICS_VERSION=$(node -p 'require("./package.json").version')
echo "Version: $METRICS_VERSION"

# Install exactly the dependencies recorded in package-lock.json. Native
# modules need their install scripts, but the hosted runner already has Chrome.
export PUPPETEER_SKIP_DOWNLOAD=true
npm ci --no-audit --no-fund
for BROWSER in google-chrome-stable google-chrome chromium chromium-browser; do
  if command -v "$BROWSER" > /dev/null 2>&1; then
    export PUPPETEER_BROWSER_PATH="$(command -v "$BROWSER")"
    break
  fi
done
if [[ -z "${PUPPETEER_BROWSER_PATH:-}" ]]; then
  echo "::error::A Chrome or Chromium executable is required to render metrics"
  exit 1
fi
echo "Browser: $PUPPETEER_BROWSER_PATH"
echo "::endgroup::"

# Run metrics directly on the GitHub-hosted runner.
node source/app/action/index.mjs
