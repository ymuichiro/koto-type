#!/usr/bin/env bash
set -euo pipefail
umask 077

command -v ffmpeg >/dev/null || { echo "ffmpeg is required" >&2; exit 127; }
device="${KOTOTYPE_AUDIO_DEVICE:-1}"
[[ "$device" =~ ^[0-9]+$ ]] || { echo "KOTOTYPE_AUDIO_DEVICE must be a device index" >&2; exit 2; }

output_root="${KOTOTYPE_AUDIO_OUTPUT_DIR:-${HOME}/Documents/KotoType/live-audio}"
mkdir -p "$output_root"
output_dir="$(mktemp -d "${output_root%/}/koto-type-live-131.XXXXXX")"
output="$output_dir/live-ja.wav"
printf '20秒録音します。開始後に読み上げてください:\n今日は午後三時ではなく午後四時です。GitHubのIssue 131は、明日午前10時に確認しますか？\n'
ffmpeg -hide_banner -loglevel error -f avfoundation -i ":$device" -t 20 -ac 1 -ar 16000 -c:a pcm_s16le "$output"
printf '録音を保存しました: %s\n' "$output"
