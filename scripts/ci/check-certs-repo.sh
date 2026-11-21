#!/usr/bin/env bash
# Ask GitHub whether MATCH_GIT_TOKEN can see MATCH_GIT_URL, then make sure the
# repo has a master branch. match refuses to create certificates in a repo
# with no commits. Nothing here prints a token, a password, or a key.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=signing-env.sh
source "$here/signing-env.sh"
signing_prepare

echo "MATCH_GIT_URL length ${#MATCH_GIT_URL}."
echo "MATCH_GIT_TOKEN length ${#MATCH_GIT_TOKEN}."
echo "MATCH_PASSWORD length ${#MATCH_PASSWORD}."
echo "APPLE_TEAM_ID length ${#APPLE_TEAM_ID}."
echo "APP_STORE_CONNECT_API_KEY_ID length ${#APP_STORE_CONNECT_API_KEY_ID}."
echo "APP_STORE_CONNECT_ISSUER_ID length ${#APP_STORE_CONNECT_ISSUER_ID}."
echo "APP_STORE_CONNECT_API_KEY_P8 length ${#APP_STORE_CONNECT_API_KEY_P8}."

fail() {
  printf '%s\n' "$1"
  exit 1
}

[[ -n "$MATCH_GIT_URL" ]] || fail "MATCH_GIT_URL is empty after trimming whitespace. The URL is the problem."
[[ -n "$MATCH_GIT_TOKEN" ]] || fail "MATCH_GIT_TOKEN is empty after trimming whitespace. The token is the problem."
[[ -n "$MATCH_PASSWORD" ]] || fail "MATCH_PASSWORD is empty after trimming whitespace."
[[ -n "$APPLE_TEAM_ID" ]] || fail "APPLE_TEAM_ID is empty after trimming whitespace."
[[ -n "$APP_STORE_CONNECT_API_KEY_ID" ]] || fail "APP_STORE_CONNECT_API_KEY_ID is empty after trimming whitespace."
[[ -n "$APP_STORE_CONNECT_ISSUER_ID" ]] || fail "APP_STORE_CONNECT_ISSUER_ID is empty after trimming whitespace."
[[ -n "$APP_STORE_CONNECT_API_KEY_P8" ]] || fail "APP_STORE_CONNECT_API_KEY_P8 is empty after trimming whitespace."

if [[ ! "$MATCH_GIT_URL" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$ ]]; then
  fail "MATCH_GIT_URL is not an https://github.com/owner/repo URL. The URL is the problem, not the token. Length is ${#MATCH_GIT_URL}. Paste https://github.com/Josh-702/uvpro-certs.git with no spaces and no extra line."
fi

echo "Certificates repo URL: ${MATCH_GIT_URL}"

body=$(mktemp)
code="000"
set +e
code=$(curl -sS --max-time 30 -o "$body" -w "%{http_code}" \
  --header "Authorization: Basic ${MATCH_GIT_BASIC_AUTHORIZATION}" \
  "${MATCH_GIT_URL}/info/refs?service=git-upload-pack")
curl_status=$?
set -e
if [[ "$curl_status" -ne 0 || -z "$code" ]]; then
  fail "Could not reach the certificates repo (curl exit ${curl_status}). The URL host is the problem, or GitHub did not answer."
fi

# GitHub answers 401 for a private repo when the token is missing or useless,
# and the body says which of the two it was. Do not print that body.
case "$code" in
  200)
    if ! grep -q "git-upload-pack" "$body"; then
      fail "MATCH_GIT_URL did not return a git repository. The URL is the problem, not the token."
    fi
    ;;
  401)
    if grep -q "Repository not found" "$body"; then
      fail "repo not found or no access (404). GitHub refused to show ${MATCH_GIT_URL}. The address is wrong, or this token cannot see that private repo."
    fi
    fail "token rejected (401). MATCH_GIT_TOKEN length is ${#MATCH_GIT_TOKEN}. The token is the problem. Paste it again with no extra line, or create a new token with Contents read and write on the certs repo."
    ;;
  403)
    fail "token rejected (403). The token reached GitHub but cannot use this repo. Give it Contents read and write on the certs repo."
    ;;
  404)
    fail "repo not found or no access (404). The URL is ${MATCH_GIT_URL}. Either that address is wrong, or this token cannot see that private repo."
    ;;
  *)
    fail "Could not reach the certificates repo (HTTP ${code}). This is a network or URL problem."
    ;;
esac

err=$(mktemp)
refs=$(mktemp)
export GIT_TERMINAL_PROMPT=0

set +e
signing_git ls-remote "$MATCH_GIT_URL" >"$refs" 2>"$err"
git_status=$?
set -e
if [[ "$git_status" -ne 0 ]]; then
  echo "git ls-remote could not read the certificates repo."
  while IFS= read -r line || [[ -n "$line" ]]; do
    signing_redact "$line"
  done <"$err"
  exit 1
fi

if [[ ! -s "$refs" ]]; then
  echo "The certificates repo is reachable and has no branches. Pushing an initial commit on master so match can store certificates there."
  work=$(mktemp -d)
  git init -q "$work"
  git -C "$work" checkout -q -b master
  git -C "$work" config user.name "Open UV Bridge"
  git -C "$work" config user.email "open-uv-bridge@users.noreply.github.com"
  git -C "$work" commit -q --allow-empty -m "Initial commit so match can store certificates"
  set +e
  signing_git -C "$work" push "$MATCH_GIT_URL" HEAD:master >"$err" 2>&1
  push_status=$?
  set -e
  if [[ "$push_status" -ne 0 ]]; then
    echo "The token can read the certificates repo but cannot push the initial commit. Match needs Contents write on that repo."
    while IFS= read -r line || [[ -n "$line" ]]; do
      signing_redact "$line"
    done <"$err"
    exit 1
  fi
  echo "Pushed an initial commit on master."
else
  echo "The certificates repo is reachable. git ls-remote found:"
  # Ref names only. The hashes are not secrets, but the names are what matter.
  awk '{ print $2 }' "$refs"
  if ! grep -q 'refs/heads/master$' "$refs"; then
    fail "The certificates repo has no master branch. match stores certificates on master. Push a master branch, or leave the repo empty so this step can create it."
  fi
fi
