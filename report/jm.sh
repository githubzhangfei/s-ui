#!/bin/bash
AES_KEY="sui2026kwrt8888"

if [[ -z "$1" ]]; then
    echo "Usage: jm.sh <iv_hex:base64_ciphertext>"
    exit 1
fi

iv_hex=$(echo "$1" | cut -d: -f1)
data=$(echo "$1" | cut -d: -f2)

if [[ -z "$iv_hex" || -z "$data" ]]; then
    echo "Error: invalid format, expected iv_hex:base64_ciphertext"
    exit 1
fi

result=$(echo "$data" | openssl enc -aes-256-cbc -d -K "$(echo -n "$AES_KEY" | xxd -p)" -iv "$iv_hex" -base64 -A 2>/dev/null)

if [[ -z "$result" ]]; then
    echo "Error: decryption failed"
    exit 1
fi

echo "$result"