#!/usr/bin/env bash
# Install the Swift 6.2.3 Ubuntu 24.04 toolchain into the directory given as $1.
# swift.org sometimes returns the signing keys gzip-compressed without curl
# decoding them, and gpg then reports "no valid OpenPGP data".
set -euo pipefail

dest=${1:?destination directory}
version=6.2.3
name="swift-${version}-RELEASE-ubuntu24.04"
base="https://download.swift.org/swift-${version}-release/ubuntu2404/swift-${version}-RELEASE"

if [[ -x "${dest}/usr/bin/swift" ]]; then
  echo "Swift already present at ${dest}"
  "${dest}/usr/bin/swift" --version
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

decode_if_gzip() {
  local file=$1
  local magic round
  for round in 1 2; do
    magic=$(od -An -t x1 -N 2 "$file" | tr -d '[:space:]')
    if [[ "$magic" != "1f8b" ]]; then
      return 0
    fi
    mv "$file" "${file}.gz"
    gunzip -c "${file}.gz" >"$file"
    rm -f "${file}.gz"
  done
}

download() {
  local url=$1 dest_file=$2 max_time=$3
  local attempt
  for attempt in 1 2 3; do
    if curl -fsSL --compressed --retry 3 --retry-delay 2 --max-time "$max_time" -o "$dest_file" "$url"; then
      return 0
    fi
    echo "Download failed (attempt ${attempt}): ${url}"
    sleep $((attempt * 2))
  done
  return 1
}

download "${base}/${name}.tar.gz" "${work}/toolchain.tar.gz" 600
download "${base}/${name}.tar.gz.sig" "${work}/toolchain.tar.gz.sig" 60
decode_if_gzip "${work}/toolchain.tar.gz.sig"

keys="${work}/keys.asc"
download "https://swift.org/keys/all-keys.asc" "$keys" 60
decode_if_gzip "$keys"
if ! grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$keys"; then
  echo "The Swift signing key download was not a PGP key."
  exit 1
fi

gpg --batch --import "$keys"
gpg --batch --verify "${work}/toolchain.tar.gz.sig" "${work}/toolchain.tar.gz"

mkdir -p "$dest"
tar -xzf "${work}/toolchain.tar.gz" -C "$dest" --strip-components=1
"${dest}/usr/bin/swift" --version
