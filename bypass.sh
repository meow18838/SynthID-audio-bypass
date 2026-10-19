set -euo pipefail
IN="$1"; OUT="$2"; SS="${3:-}"; LEN="${4:-}"
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN")
IR="$(mktemp --suffix=.wav)"
python3 - "$IR" <<'EOF'
import sys, numpy as np, soundfile as sf
sr = 44100; n = int(0.7 * sr); t = np.arange(n) / sr
r = np.random.default_rng(11)
tail = r.normal(0, 1, (n, 2)) * np.exp(-6.9 * t / 0.5)[:, None] * 0.35
ir = tail.copy(); ir[0] += [1.0, 1.0]
for d, g in ((0.003, 0.45), (0.0071, 0.3), (0.012, 0.2)):   ir[int(d * sr)] += [g, g * 0.8]
for d, g in ((0.0046, 0.4), (0.0089, 0.25), (0.015, 0.18)): ir[int(d * sr)] += [g * 0.8, g]
ir /= np.abs(ir).sum(0).max()
sf.write(sys.argv[1], ir, sr)
EOF
ffmpeg -y -v error -i "$IN" -i "$IR" -filter_complex "\
[0:a]aformat=channel_layouts=stereo,highpass=f=35,lowpass=f=16000,bass=g=2:f=70,asoftclip=type=tanh:threshold=0.85[s];\
[s]pan=stereo|c0=0.85*c0+0.15*c1|c1=0.15*c0+0.85*c1[spk];\
[spk][1:a]afir=dry=10:wet=10[r];\
anoisesrc=color=pink:amplitude=0.0015:duration=${DUR}:sample_rate=44100:seed=21,aformat=channel_layouts=stereo[n];\
[r][n]amix=inputs=2:duration=first:normalize=0,\
acompressor=threshold=-24dB:ratio=2:attack=10:release=300:makeup=2,aresample=44100" \
-ac 2 -ar 44100 -b:a 128k "${OUT%.mp3}_full.mp3"
rm -f "$IR"
if [ -n "$SS" ]; then
  ffmpeg -y -v error -ss "$SS" -t "$LEN" -i "${OUT%.mp3}_full.mp3" -c copy "$OUT"
else
  mv "${OUT%.mp3}_full.mp3" "$OUT"
fi
echo "wrote $OUT"
