# Shared by the certificates check and the TestFlight upload.
# Sourced, not executed. Prints no secret. Lengths are fine.

# Drop every whitespace character. A GitHub URL and a personal access token
# never contain one, and an iPhone paste often adds a trailing newline.
signing_strip_ws() {
  printf '%s' "$1" | tr -d '[:space:]'
}

# Trim only the ends, so a passphrase may still contain spaces.
signing_trim_edges() {
  local s=$1
  s=${s//$'\r'/}
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

signing_mask() {
  local value=$1
  if [[ -n "$value" ]]; then
    printf '%s\n' "::add-mask::${value}"
  fi
}

signing_prepare() {
  MATCH_GIT_URL=$(signing_strip_ws "${MATCH_GIT_URL:-}")
  MATCH_GIT_TOKEN=$(signing_strip_ws "${MATCH_GIT_TOKEN:-}")
  MATCH_PASSWORD=$(signing_trim_edges "${MATCH_PASSWORD:-}")
  APPLE_TEAM_ID=$(signing_strip_ws "${APPLE_TEAM_ID:-}")
  APP_STORE_CONNECT_API_KEY_ID=$(signing_strip_ws "${APP_STORE_CONNECT_API_KEY_ID:-}")
  APP_STORE_CONNECT_ISSUER_ID=$(signing_strip_ws "${APP_STORE_CONNECT_ISSUER_ID:-}")
  APP_STORE_CONNECT_API_KEY_P8=$(signing_trim_edges "${APP_STORE_CONNECT_API_KEY_P8:-}")
  if [[ -n "$APP_STORE_CONNECT_API_KEY_P8" ]]; then
    APP_STORE_CONNECT_API_KEY_P8="${APP_STORE_CONNECT_API_KEY_P8}"$'\n'
  fi

  export MATCH_GIT_URL MATCH_GIT_TOKEN MATCH_PASSWORD APPLE_TEAM_ID
  export APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_API_KEY_P8

  # Same header match sends: username x-access-token, password the PAT.
  MATCH_GIT_BASIC_AUTHORIZATION=""
  if [[ -n "$MATCH_GIT_TOKEN" ]]; then
    MATCH_GIT_BASIC_AUTHORIZATION=$(printf 'x-access-token:%s' "$MATCH_GIT_TOKEN" | base64 | tr -d '[:space:]')
  fi
  export MATCH_GIT_BASIC_AUTHORIZATION
  export MATCH_GIT_BRANCH=master
  export MATCH_GIT_FULL_NAME="Open UV Bridge"
  export MATCH_GIT_USER_EMAIL="open-uv-bridge@users.noreply.github.com"

  signing_mask "$MATCH_GIT_TOKEN"
  signing_mask "$MATCH_GIT_BASIC_AUTHORIZATION"
  signing_mask "$MATCH_PASSWORD"
}

# Remove every copy of a literal secret from one line. Quoted patterns stay
# literal, including slash and plus, which show up in base64.
signing_replace() {
  local line=$1
  local secret=$2
  local out=""
  if [[ -z "$secret" ]]; then
    printf '%s' "$line"
    return
  fi
  while [[ "$line" == *"$secret"* ]]; do
    out="${out}${line%%"$secret"*}[redacted]"
    line=${line#*"$secret"}
  done
  printf '%s' "${out}${line}"
}

signing_redact() {
  local line=$1
  line=$(signing_replace "$line" "$MATCH_GIT_TOKEN")
  line=$(signing_replace "$line" "$MATCH_GIT_BASIC_AUTHORIZATION")
  printf '%s\n' "$line"
}
