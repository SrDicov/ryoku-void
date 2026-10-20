#!/usr/bin/env bash
# hermetic test for the stash quality picker: stash-cobalt.sh's probe
# subcommand in each download mode, and the optional format selector download
# now takes.
#
# Nothing here touches the network. yt-dlp and curl are stubbed on PATH: the
# yt-dlp stub answers -J from a canned JSON fixture and, for a download, records
# the exact argv it was handed; the curl stub records cobalt's request body and
# refuses the transfer, so the cobalt path is observable and the yt-dlp fallback
# still runs.
#
# The load-bearing assertions are the ARGV ones. A picker that shows a 720p tier
# and then downloads whatever yt-dlp felt like is worse than no picker, so the
# selector must arrive as one -f argument, and a download with no selector must
# be the command it always was.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../ryoku/shell/scripts/stash-cobalt.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() {
  echo "FAIL: $1" >&2
  exit 1
}

bin="$tmp/bin"
mkdir -p "$bin"

# yt-dlp: -J is the probe, anything else is a download. A download has to leave a
# file behind or the script reports nothing saved, so the stub fabricates one
# from the -o template. Each argv element lands on its own line: the selector
# carries [ and + and must arrive as a single element, not as a split word.
cat >"$bin/yt-dlp" <<EOF
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a" >>"$tmp/ytdlp.argv"; done
case " \$* " in
  *" -J "*)
    if [ "\$FAKE_JSON" = fail ]; then
      echo "ERROR: [youtube] abc: Video unavailable" >&2
      exit 1
    fi
    cat "\$FAKE_JSON"
    ;;
  *)
    if [ "\$FAKE_DL" = fail ]; then
      echo "ERROR: [youtube] abc: Video unavailable" >&2
      exit 1
    fi
    dir=""; name=""
    while [ \$# -gt 0 ]; do
      case "\$1" in -P) dir="\$2"; shift 2 ;; -o) name="\$2"; shift 2 ;; *) shift ;; esac
    done
    mkdir -p "\$dir"
    printf '[download] 100.0%% of 1.00MiB at 1MiB/s ETA 00:00\n' >"\$dir/\${name%%.*}.mp4"
    ;;
esac
EOF
chmod +x "$bin/yt-dlp"

# notify-send: records every argument it was handed, one per line, so a test can
# read a notification body back. The cancel case further down prepends its own
# stub to PATH, and that one wins, which is what keeps its pid file working.
cat >"$bin/notify-send" <<EOF
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a" >>"$tmp/notify.args"; done
exit 0
EOF
chmod +x "$bin/notify-send"

# curl: the instance answers its status probe, but a POST records its body and
# declines. That is the state the download path must survive, and it leaves the
# request body on disk to be asserted on. TUNNEL switches the POST to a real
# transfer so the fetch phase itself can be driven; a transfer writes the bytes
# it has before it hangs, because that half-written file is exactly what a
# cancelled download must not leave behind.
cat >"$bin/curl" <<EOF
#!/bin/sh
prev=""; ofile=""
for a in "\$@"; do
  [ "\$prev" = -d ] && printf '%s' "\$a" >"$tmp/cobalt.body"
  [ "\$prev" = -o ] && ofile="\$a"
  prev="\$a"
done
case " \$* " in
  *" -d "*)
    if [ -e "$tmp/TUNNEL" ]; then
      echo '{"status":"tunnel","url":"http://dl.example/f","filename":"a.mp4"}'
      exit 0
    fi
    exit 22 ;;
  *" -o "*)
    printf 'partial-bytes' >"\$ofile"
    echo \$\$ >"$tmp/curl.pid"
    sleep 60
    exit 0
    ;;
  *) echo '{"services":["youtube"]}' ;;
esac
EOF
chmod +x "$bin/curl"

export PATH="$bin:$PATH"
export STASH_DIR="$tmp/stash"
# probe answers are cached per URL, and this suite reuses one URL across
# fixtures, so each probe case gets a cache dir of its own and no case can
# read another's answer. the direct invocations below share this default.
export STASH_CACHE_DIR="$tmp/cache.default"

# value at a jq path of a probe payload
val() { printf '%s' "$1" | jq -r "$2"; }
# a probe against one fixture, in a cache dir of its own
probe() { FAKE_JSON="$tmp/$1" STASH_CACHE_DIR="$(mktemp -d "$tmp/cache.XXXXXX")" \
  bash "$script" probe "https://example.com/v"; }
# a download, with the cobalt transfer declined by the stub
dl() { bash "$script" download "https://example.com/v" "$@" >/dev/null 2>&1 || true; }
# how many times an argv element was handed to the stub; a call log that was
# never created is the strongest statement there is that it was never called
argv() {
  [ -e "$tmp/ytdlp.argv" ] || {
    printf '0\n'
    return
  }
  awk -v a="$1" '$0==a{c++} END{print c+0}' "$tmp/ytdlp.argv"
}
# the element following -f, or nothing when -f is absent
fmt_arg() { awk '/^-f$/{getline; print; exit}' "$tmp/ytdlp.argv"; }

# ---- one TIERS line, every mode on it ---------------------------------------
cat >"$tmp/tiers.json" <<'EOF'
{"title":"Three Ladders","duration":3600,"formats":[
{"format_id":"399","vcodec":"avc1","height":2160,"tbr":18000},
{"format_id":"248","vcodec":"vp9","height":1440,"tbr":9000},
{"format_id":"137","vcodec":"avc1","height":1080,"tbr":4500},
{"format_id":"140","acodec":"mp4a","vcodec":"none","abr":128}
]}
EOF
out="$(probe tiers.json)"
[[ "$(wc -l <<<"$out")" -eq 1 ]] || fail "probe should print exactly one line, got: $out"
[[ "$(cut -f1 <<<"$out")" == TIERS ]] || fail "probe should emit a TIERS line, got: $out"
payload="$(cut -f2- <<<"$out")"
[[ "$(val "$payload" '.duration')" == 3600 ]] || fail "duration should reach the picker"
[[ "$(val "$payload" '.title')" == "Three Ladders" ]] || fail "title should reach the picker"
[[ "$(val "$payload" '.tiers | keys | join(",")')" == "audio,auto,mute" ]] ||
  fail "one extraction must answer every mode, got: $(val "$payload" '.tiers | keys | join(",")')"

# the three modes disagree about audio and nothing else: no height under 720
# exists to be an average, so the middle tier is the median of what is there,
# and the smallest tier is the smallest rung offered.
[[ "$(val "$payload" '[.tiers.auto[].key] | join(",")')" == "best,avg,low" ]] || fail "three video tiers expected"
[[ "$(val "$payload" '[.tiers.auto[].height] | join(",")')" == "2160,1440,1080" ]] || fail "median and minimum tiers wrong"
[[ "$(val "$payload" '[.tiers.mute[].height] | join(",")')" == "2160,1440,1080" ]] || fail "mute picks the same rungs"
[[ "$(val "$payload" '.tiers.auto[0].fmt')" == "bv[height<=2160]+ba/bv*[height<=2160]" ]] ||
  fail "a video tier must merge the best video with the best audio"
[[ "$(val "$payload" '.tiers.mute[0].fmt')" == "bv[height<=2160]/bv*[height<=2160]" ]] ||
  fail "a muted tier must be video-only"
# 4500 + 128 kbit/s over an hour for the merge, video alone for the mute
[[ "$(val "$payload" '.tiers.auto[2].sizeMB')" == 2082.6 ]] || fail "size estimate math is wrong"
[[ "$(val "$payload" '.tiers.mute[2].sizeMB')" == 2025 ]] || fail "mute size must omit the audio bitrate"

# no format_id survives into any selector: the probe and the download are two
# extractions and YouTube rotates ids between them, so a pinned id resolves here
# and vanishes there.
if grep -q "format_id" <<<"$payload"; then
  fail "a selector must cap a quality, not pin a format id: $(val "$payload" '.tiers.auto[0].fmt')"
fi

# ---- an ordinary ladder: the top rung, the best under 720, the cheapest kept
cat >"$tmp/ladder.json" <<'EOF'
{"title":"Ladder","duration":3600,"formats":[
{"format_id":"137","vcodec":"avc1","height":1080,"tbr":4500},
{"format_id":"136","vcodec":"avc1","height":720,"tbr":2500},
{"format_id":"134","vcodec":"avc1","height":360,"tbr":600},
{"format_id":"160","vcodec":"avc1","height":240,"tbr":300},
{"format_id":"140","acodec":"mp4a","vcodec":"none","abr":128}
]}
EOF
payload="$(probe ladder.json | cut -f2-)"
[[ "$(val "$payload" '[.tiers.auto[].height] | join(",")')" == "1080,720,360" ]] ||
  fail "the ladder must be the top rung, the best under 720, then the cheapest kept"
[[ "$(val "$payload" '.tiers.auto[2].sizeMB')" == 327.6 ]] || fail "size estimate math is wrong again"

# ---- a size the format states wins over the bitrate guess -------------------
cat >"$tmp/sized.json" <<'EOF'
{"title":"Stated","duration":3600,"formats":[
{"format_id":"137","vcodec":"avc1","height":1080,"tbr":4500,"filesize_approx":145234567},
{"format_id":"140","acodec":"mp4a","vcodec":"none","abr":128}
]}
EOF
payload="$(probe sized.json | cut -f2-)"
[[ "$(val "$payload" '.tiers.auto[0].sizeMB')" == 145.2 ]] || fail "a stated filesize must be used as the size"

# ---- tiers that land on the same height are one tier -------------------------
cat >"$tmp/collide.json" <<'EOF'
{"title":"Two Rungs","duration":3600,"formats":[
{"format_id":"137","vcodec":"avc1","height":1080,"tbr":4500},
{"format_id":"160","vcodec":"avc1","height":240,"tbr":300},
{"format_id":"140","acodec":"mp4a","vcodec":"none","abr":128}
]}
EOF
payload="$(probe collide.json | cut -f2-)"
[[ "$(val "$payload" '.tiers.auto | length')" == 2 ]] || fail "the low tier duplicated the avg tier's height"
[[ "$(val "$payload" '[.tiers.auto[].height] | join(",")')" == "1080,240" ]] || fail "dedupe must keep the higher key"

# ---- a source with no duration has no size to quote --------------------------
cat >"$tmp/live.json" <<'EOF'
{"title":"Live","formats":[
{"format_id":"137","vcodec":"avc1","height":1080,"tbr":4500},
{"format_id":"140","acodec":"mp4a","vcodec":"none","abr":128}
]}
EOF
payload="$(probe live.json | cut -f2-)"
[[ "$(val "$payload" '.duration')" == null ]] || fail "an endless source reports no duration"
[[ "$(val "$payload" '.tiers.auto[0].sizeMB')" == null ]] || fail "an endless source has no size to quote"

# ---- the audio list: bitrate rungs, no heights ------------------------------
cat >"$tmp/audio.json" <<'EOF'
{"title":"A Track","duration":240,"formats":[
{"format_id":"320","acodec":"m4a","vcodec":"none","abr":320},
{"format_id":"140","acodec":"mp4a","vcodec":"none","abr":128},
{"format_id":"251l","acodec":"opus","vcodec":"none","abr":50}
]}
EOF
payload="$(probe audio.json | cut -f2-)"
[[ "$(val "$payload" '[.tiers.audio[].key] | join(",")')" == "high,std,light" ]] ||
  fail "three audio rungs expected when the source reaches all three"
[[ "$(val "$payload" '[.tiers.audio[].bitrate] | join(",")')" == "320,128,64" ]] ||
  fail "the rungs are 320, 128, 64"
[[ "$(val "$payload" '[.tiers.audio[] | select(has("height"))] | length')" == 0 ]] ||
  fail "an audio tier carries no height"
# each rung caps its own bitrate, whatever the ids happen to be this time
[[ "$(val "$payload" '[.tiers.audio[].fmt] | join(",")')" == "ba[abr<=320]/ba,ba[abr<=128]/ba,ba[abr<=64]/ba" ]] ||
  fail "each rung must cap its bitrate"
[[ "$(val "$payload" '.tiers.audio[1].sizeMB')" == 3.8 ]] || fail "audio size must come from the bitrate and duration"

# a rung is served by the strongest stream at or below it, so rungs may share a
# stream; a rung above what the source ever offered is dropped rather than faked
cat >"$tmp/coarse.json" <<'EOF'
{"title":"Coarse Audio","duration":600,"formats":[
{"format_id":"137","vcodec":"avc1","height":1080,"tbr":4500},
{"format_id":"600","acodec":"m4a","vcodec":"none","abr":320}
]}
EOF
payload="$(probe coarse.json | cut -f2-)"
[[ "$(val "$payload" '[.tiers.audio[].key] | join(",")')" == "high,std,light" ]] ||
  fail "one stream may serve every rung"
[[ "$(val "$payload" '[.tiers.audio[].sizeMB] | unique | join(",")')" == 24 ]] ||
  fail "rungs sharing a stream must be priced at that stream's bitrate"

# the strongest stream here is 160, so the 320 rung is not on the menu
cat >"$tmp/medium.json" <<'EOF'
{"title":"Medium Audio","duration":240,"formats":[
{"format_id":"137","vcodec":"avc1","height":1080,"tbr":4500},
{"format_id":"251","acodec":"opus","vcodec":"none","abr":160},
{"format_id":"140","acodec":"mp4a","vcodec":"none","abr":128}
]}
EOF
payload="$(probe medium.json | cut -f2-)"
[[ "$(val "$payload" '[.tiers.audio[].key] | join(",")')" == "std,light" ]] ||
  fail "a rung above the strongest stream must be dropped, not faked"

# muxed formats can report only tbr. They must not displace the audio-only
# streams that back the bitrate rungs.
cat >"$tmp/muxed.json" <<'EOF'
{"title":"Muxed","duration":240,"formats":[
{"format_id":"137","vcodec":"avc1","acodec":"none","height":1080,"tbr":4500,"abr":0},
{"format_id":"18","vcodec":"avc1","acodec":"mp4a","height":360,"tbr":500,"abr":null},
{"format_id":"251","acodec":"opus","vcodec":"none","tbr":130,"abr":130}
]}
EOF
payload="$(probe muxed.json | cut -f2-)"
[[ "$(val "$payload" '[.tiers.audio[].key] | join(",")')" == "std,light" ]] ||
  fail "a muxed format must not hide the audio streams"

# Some sites offer no audio-only format. Keep one honest extraction choice and
# let mute fall back to the muxed video stream.
cat >"$tmp/muxed-only.json" <<'EOF'
{"title":"Muxed Only","duration":240,"formats":[
{"format_id":"hd","vcodec":"avc1","acodec":"mp4a","height":1080,"tbr":4500,"abr":null},
{"format_id":"sd","vcodec":"avc1","acodec":"mp4a","height":480,"tbr":900,"abr":null}
]}
EOF
payload="$(probe muxed-only.json | cut -f2-)"
[[ "$(val "$payload" '[.tiers.audio[].key] | join(",")')" == "audio" ]] ||
  fail "a muxed-only source must offer audio extraction"
[[ "$(val "$payload" '.tiers.audio[0].fmt')" == "ba/b" ]] ||
  fail "muxed-only audio must fall back to the best voiced format"
[[ "$(val "$payload" '.tiers.audio[0].bitrate, .tiers.audio[0].sizeMB')" == "$(printf 'null\nnull')" ]] ||
  fail "muxed-only audio must not invent a bitrate or size"
[[ "$(val "$payload" '.tiers.mute[0].fmt')" == "bv[height<=1080]/bv*[height<=1080]" ]] ||
  fail "muxed-only mute must fall back to a voiced video format"

# a link with no video has nothing to ladder, so every mode answers with the
# audio rungs rather than an empty card the user cannot act on
payload="$(probe audio.json | cut -f2-)"
for m in auto audio mute; do
  [[ "$(val "$payload" "[.tiers.${m}[].key] | join(\",\")")" == "high,std,light" ]] ||
    fail "an audio-only link under $m should offer the audio rungs"
done

# a silent video has nothing to merge, and no audio rung to offer
cat >"$tmp/silent.json" <<'EOF'
{"title":"No Sound","duration":1000,"formats":[
{"format_id":"137","vcodec":"avc1","height":1080,"tbr":4500},
{"format_id":"136","vcodec":"avc1","height":720,"tbr":2500}
]}
EOF
payload="$(probe silent.json | cut -f2-)"
[[ "$(val "$payload" ".tiers.audio | length")" == 0 ]] || fail "a silent source offers no audio rung"
[[ "$(val "$payload" '.tiers.mute[0].sizeMB')" == 562.5 ]] || fail "a silent source is priced without audio"

# ---- a bad link is one ERROR line and a nonzero exit ------------------------
rc=0
out="$(FAKE_JSON=fail bash "$script" probe "https://example.com/v" 2>/dev/null)" || rc=$?
[[ $rc -ne 0 ]] || fail "a failed probe must exit nonzero"
[[ "$(cut -f1 <<<"$out")" == ERROR ]] || fail "a failed probe must emit an ERROR line, got: $out"
grep -q "Video unavailable" <<<"$out" ||
  fail "the probe error must carry yt-dlp's message, got: $out"

rc=0
out="$(bash "$script" probe 2>/dev/null)" || rc=$?
[[ $rc -eq 2 ]] || fail "probe with no link should exit 2 (rc=$rc)"
[[ "$(cut -f1 <<<"$out")" == ERROR ]] || fail "probe with no link must say so"

# ---- the probe is yt-dlp's alone: a configured cobalt never enters it --------
rm -f "$tmp/cobalt.body"
out="$(COBALT_API_URL=http://localhost:9 probe tiers.json)"
[[ "$(cut -f1 <<<"$out")" == TIERS ]] || fail "probe must work with a cobalt URL configured"
[[ ! -e "$tmp/cobalt.body" ]] || fail "probe must never talk to cobalt"

# ---- the answer is cached per link, so a known link costs no extraction ------
cacheurl="https://example.com/cached/v"
otherurl="https://example.com/other/v"
cachedir="$tmp/cache.hit"
cachekey="$(printf '%s' "$cacheurl" | sha256sum | cut -d' ' -f1)"
# STASH_CACHE_DIR is the base the helper keeps its own entries under
cachefile="$cachedir/stash-probe/$cachekey.json"
# the payload a probe line carries, on its own
tiers_of() { cut -f2- <<<"$1"; }

# miss first: the stub is reached, and the answer it gave lands in the file
rm -f "$tmp/ytdlp.argv"
out1="$(FAKE_JSON="$tmp/tiers.json" STASH_CACHE_DIR="$cachedir" bash "$script" probe "$cacheurl")"
[[ "$(argv '-J')" == 1 ]] || fail "a first probe must extract exactly once"
[[ -f "$cachefile" ]] || fail "a successful probe must write its cache file"
first="$(tiers_of "$out1")"
jq -e . <<<"$first" >/dev/null || fail "the payload must be one line of json"
[[ "$(jq -c '.payload' <"$cachefile")" == "$first" ]] ||
  fail "the cached payload must be the tiers that were emitted"
[[ "$(val "$(cat "$cachefile")" '.cached_at | type')" == number ]] ||
  fail "the entry must record when it was written"

# the same link again: the same line, and no extraction at all
rm -f "$tmp/ytdlp.argv"
out2="$(STASH_CACHE_DIR="$cachedir" bash "$script" probe "$cacheurl")"
[[ "$(argv '-J')" == 0 ]] || fail "a cached link must not reach yt-dlp again"
[[ "$out2" == "$out1" ]] || fail "a cache hit must serve the same TIERS line, got: $out2"

# an entry older than its ttl is a miss, and the re-probe restamps it. the
# fixture changes too, so a stale hit would show up in the answer.
stale=$(($(date +%s) - 90000))
jq -c --argjson ts "$stale" '{cached_at: $ts, payload: .payload}' "$cachefile" >"$cachefile.new"
mv -f "$cachefile.new" "$cachefile"
rm -f "$tmp/ytdlp.argv"
out3="$(FAKE_JSON="$tmp/ladder.json" STASH_CACHE_DIR="$cachedir" bash "$script" probe "$cacheurl")"
[[ "$(argv '-J')" == 1 ]] || fail "a stale entry must be probed again"
[[ "$(val "$(tiers_of "$out3")" '.title')" == "Ladder" ]] ||
  fail "a stale entry must be replaced by the fresh answer, got: $(tiers_of "$out3")"
[[ "$(val "$(cat "$cachefile")" '.cached_at')" -gt "$stale" ]] ||
  fail "a re-probe must restamp the entry"

# a ttl of zero expires everything, so the switch itself is the thing under test
rm -f "$tmp/ytdlp.argv"
out4="$(FAKE_JSON="$tmp/tiers.json" STASH_CACHE_DIR="$cachedir" STASH_PROBE_TTL=0 \
  bash "$script" probe "$cacheurl")"
[[ "$(argv '-J')" == 1 ]] || fail "STASH_PROBE_TTL=0 must expire every entry"
[[ "$(val "$(tiers_of "$out4")" '.title')" == "Three Ladders" ]] ||
  fail "an expired entry must answer from a fresh extraction"
[[ "$(val "$(cat "$cachefile")" '.cached_at')" -ge "$stale" ]] ||
  fail "an expired entry must be restamped by the extraction that replaced it"

# a second link is a second entry beside the first, each under its own key
akey="$cachekey"
bkey="$(printf '%s' "$otherurl" | sha256sum | cut -d' ' -f1)"
[[ "$akey" != "$bkey" ]] || fail "two links must not share a cache key"
FAKE_JSON="$tmp/ladder.json" STASH_CACHE_DIR="$cachedir" bash "$script" probe "$otherurl" >/dev/null
[[ -f "$cachedir/stash-probe/$bkey.json" ]] ||
  fail "each link needs its own entry, got: $(ls "$cachedir/stash-probe")"
[[ "$(val "$(cat "$cachefile")" '.payload.title')" == "Three Ladders" ]] ||
  fail "one link's answer must not overwrite another's"
[[ "$(val "$(cat "$cachedir/stash-probe/$bkey.json")" '.payload.title')" == "Ladder" ]] ||
  fail "an entry must hold its own link's tiers"

# a failed probe caches nothing: no negative entries to serve a bad answer
faildir="$tmp/cache.fail"
rc=0
FAKE_JSON=fail STASH_CACHE_DIR="$faildir" bash "$script" probe "$cacheurl" >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "a failed probe must exit nonzero"
if [ -d "$faildir/stash-probe" ] && [ -n "$(ls -A "$faildir/stash-probe")" ]; then
  fail "a failed probe must not leave a cache entry: $(ls "$faildir/stash-probe")"
fi

# anything the reader cannot use is a miss, and the file is replaced. each entry
# is unreadable for exactly one reason, and the clock is fresh so a stale
# timestamp can never be what turns a bad entry into a miss.
now_s=$(date +%s)
badentries=(
  'not json at all'
  "{\"cached_at\":$now_s,\"payload\":{\"title\":\"No Tiers\"}}"
  "{\"cached_at\":\"soon\",\"payload\":{\"tiers\":{\"auto\":[{\"key\":\"best\"}]}}}"
)
for bad in "${badentries[@]}"; do
  baddir="$tmp/cache.bad"
  rm -rf "$baddir"
  mkdir -p "$baddir/stash-probe"
  printf '%s' "$bad" >"$baddir/stash-probe/$akey.json"
  rm -f "$tmp/ytdlp.argv"
  bout="$(FAKE_JSON="$tmp/tiers.json" STASH_CACHE_DIR="$baddir" bash "$script" probe "$cacheurl")"
  [[ "$(argv '-J')" == 1 ]] || fail "an unusable entry must be probed again: $bad"
  [[ "$(val "$(tiers_of "$bout")" '.title')" == "Three Ladders" ]] ||
    fail "an unusable entry must answer from the fresh extraction: $bad"
  [[ "$(val "$(cat "$baddir/stash-probe/$akey.json")" '.payload.title')" == "Three Ladders" ]] ||
    fail "an unusable entry must be overwritten: $bad"
done

# a cache the user cannot write to is a slow probe, not a broken one
rodir="$tmp/readonly"
mkdir -p "$rodir"
chmod 500 "$rodir"
rc=0
out5="$(FAKE_JSON="$tmp/tiers.json" STASH_CACHE_DIR="$rodir/sub" bash "$script" probe "$cacheurl" 2>/dev/null)" || rc=$?
[[ $rc -eq 0 ]] || fail "an unwritable cache dir must not fail the probe (rc=$rc)"
[[ "$(cut -f1 <<<"$out5")" == TIERS ]] || fail "an unwritable cache dir must still emit tiers, got: $out5"
[[ "$(val "$(tiers_of "$out5")" '.title')" == "Three Ladders" ]] ||
  fail "an unwritable cache dir must still answer with the fresh tiers"
if [ "$(id -u)" -ne 0 ] && [ -e "$rodir/sub" ]; then fail "an unwritable cache dir must stay unwritable"; fi
chmod 700 "$rodir"

# ---- download without a selector is exactly the command it always was -------
sel720='bv[height<=720]+ba/bv*[height<=720]'
selmute='bv[height<=480]/bv*[height<=480]'
selaudio='ba[abr<=128]/ba'

rm -f "$tmp/ytdlp.argv"
dl auto
[[ "$(argv '-f')" == 0 ]] || fail "a selector-less auto download must pass no -f"
[[ "$(argv '--merge-output-format')" -eq 1 ]] || fail "auto download must still merge to mp4"

rm -f "$tmp/ytdlp.argv"
dl mute
[[ "$(fmt_arg)" == 'bv*' ]] || fail "a selector-less mute download must keep bv*"

rm -f "$tmp/ytdlp.argv"
dl audio
[[ "$(fmt_arg)" == 'ba/b' ]] || fail "audio download must fall back through muxed formats, got: $(fmt_arg)"
[[ "$(argv '-x')" -eq 1 ]] || fail "audio download must extract without re-encoding"
[[ "$(argv '--audio-format')" -eq 0 ]] || fail "audio download must keep the source codec"

# ---- with a selector, the tier the user picked is the tier yt-dlp gets ------
rm -f "$tmp/ytdlp.argv"
dl auto "$sel720"
[[ "$(argv '-f')" -eq 1 ]] || fail "auto with a selector must pass exactly one -f"
[[ "$(fmt_arg)" == "$sel720" ]] || fail "the selector must arrive as one argv element, got: $(fmt_arg)"
[[ "$(argv '--merge-output-format')" -eq 1 ]] || fail "a selected auto download must still merge to mp4"

rm -f "$tmp/ytdlp.argv"
dl mute "$selmute"
[[ "$(fmt_arg)" == "$selmute" ]] || fail "mute with a selector must use it"

# the audio rung picks the stream; nothing rewrites it afterwards
rm -f "$tmp/ytdlp.argv"
dl audio "$selaudio"
[[ "$(fmt_arg)" == "$selaudio/b" ]] || fail "selected audio must fall back through muxed formats"
[[ "$(argv '-x')" -eq 1 ]] || fail "a selected audio download must extract without re-encoding"

# ---- cobalt takes a rung, so the selector's height has to reach the body ----
rm -f "$tmp/cobalt.body"
dl auto "$sel720"
grep -q '"videoQuality":"720"' "$tmp/cobalt.body" ||
  fail "cobalt should be asked for the tier's height, got: $(cat "$tmp/cobalt.body")"
grep -q '"audioFormat":"best"' "$tmp/cobalt.body" ||
  fail "cobalt must be asked for the original audio stream, got: $(cat "$tmp/cobalt.body")"
if grep -q 'audioBitrate' "$tmp/cobalt.body"; then
  fail "audioBitrate is ignored for best audio and must not be sent: $(cat "$tmp/cobalt.body")"
fi

for rung in 1440 2160; do
  rm -f "$tmp/cobalt.body"
  dl auto "bv[height<=$rung]+ba/bv*[height<=$rung]"
  grep -q "\"videoQuality\":\"$rung\"" "$tmp/cobalt.body" ||
    fail "cobalt should receive its $rung rung, got: $(cat "$tmp/cobalt.body")"
done

# a selector from a site whose ladder has no rung cobalt knows keeps the default
rm -f "$tmp/cobalt.body"
dl auto 'bv[height<=900]+ba/bv*[height<=900]'
grep -q '"videoQuality":"1080"' "$tmp/cobalt.body" ||
  fail "an off-ladder height must keep cobalt's default, got: $(cat "$tmp/cobalt.body")"

rm -f "$tmp/cobalt.body"
dl audio "$selaudio"
grep -q '"videoQuality":"1080"' "$tmp/cobalt.body" ||
  fail "an audio download must keep cobalt's default quality"
grep -q '"downloadMode":"audio"' "$tmp/cobalt.body" ||
  fail "an audio download must select audio mode, got: $(cat "$tmp/cobalt.body")"
grep -q '"audioFormat":"best"' "$tmp/cobalt.body" ||
  fail "an audio download must ask for the untranscoded stream, got: $(cat "$tmp/cobalt.body")"

# ---- the notification names the download -------------------------------------
# STASH_TITLE is what the shell passes from the probe; without it the script
# falls back to the file the job landed, extension off. Bodies are read back out
# of the notify-send recorder, one argument per line.
rm -f "$tmp/notify.args"
STASH_TITLE='A Video Title' bash "$script" download "https://example.com/v" auto >/dev/null 2>&1
grep -Fx 'Downloaded: A Video Title' "$tmp/notify.args" >/dev/null ||
  fail "a notification must name the video the shell passed, got: $(tr '\n' '|' <"$tmp/notify.args")"

# a title with a dot in it is a title, not a filename: only the fallback loses an
# extension
rm -f "$tmp/notify.args"
STASH_TITLE='Movie.v2 final' bash "$script" download "https://example.com/v" auto >/dev/null 2>&1
grep -Fx 'Downloaded: Movie.v2 final' "$tmp/notify.args" >/dev/null ||
  fail "a probed title must keep its dots, got: $(tr '\n' '|' <"$tmp/notify.args")"

# no title from the shell, so the file the stub landed stands in, extension off
rm -f "$tmp/notify.args"
bash "$script" download "https://example.com/v" auto >/dev/null 2>&1
grep -F 'Downloaded: %(title)' "$tmp/notify.args" >/dev/null ||
  fail "without a probed title the landed filename must stand in, got: $(tr '\n' '|' <"$tmp/notify.args")"
if grep -Fq 'Downloaded:' "$tmp/notify.args" && grep -Fq '%(title).mp4' "$tmp/notify.args"; then
  fail "the fallback must lose its extension, got: $(tr '\n' '|' <"$tmp/notify.args")"
fi

# a failed download is still a download, so the notification names it too, and the
# queue line the UI reads still says what happened
rm -f "$tmp/notify.args"
rc=0
out="$(FAKE_DL=fail STASH_TITLE='A Title' bash "$script" download "https://example.com/v" auto 2>/dev/null)" || rc=$?
[[ $rc -ne 0 ]] || fail "a failed download must exit nonzero"
grep -q '^START' <<<"$out" || fail "a failed download must still start its row, got: $out"
grep -q '^ERROR' <<<"$out" || fail "a failed download must still emit its ERROR line, got: $out"
grep -Fx 'Download failed: A Title' "$tmp/notify.args" >/dev/null ||
  fail "a failure notification must name the download too, got: $(tr '\n' '|' <"$tmp/notify.args")"

# ---- the row keeps its own name: START arrives without one ------------------
out="$(bash "$script" download "https://example.com/v" auto 2>/dev/null || true)"
[[ "$(head -1 <<<"$out")" == "$(printf 'START\t')" ]] ||
  fail "START must carry no name, got: $(head -1 <<<"$out")"
if grep -q "fetching link" <<<"$out"; then fail "the placeholder name must be gone"; fi

# ---- a cancelled job dies with the script, transfer and all ----------------
alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
# wait for a stub to record its pid, so the test never races the startup
await() {
  local i=0
  while [ ! -e "$1" ] && [ $i -lt 100 ]; do
    sleep 0.05
    i=$((i + 1))
  done
}
# the stubs sleep a minute, so anything under this is the trap and not the wait
prompt() { [ "$((SECONDS - $1))" -lt 10 ]; }

# the yt-dlp fallback: a stub that hangs, with a child of its own, so a kill that
# only reached the script would leave both running. it drops a half-written file
# into the work dir and only then publishes its pid, so a test can never look
# before the leak it is hunting has already happened.
sleepbin="$tmp/sleepbin"
mkdir -p "$sleepbin"
cat >"$sleepbin/yt-dlp" <<EOF
#!/bin/sh
dir=""
while [ \$# -gt 0 ]; do
  case "\$1" in -P) dir="\$2"; shift 2 ;; *) shift ;; esac
done
[ -n "\$dir" ] && printf 'partial-bytes' >"\$dir/partial.mp4"
echo \$\$ >"$tmp/ytdlp.pid"
sleep 60 &
echo \$! >"$tmp/ytdlp.kid"
wait
EOF
chmod +x "$sleepbin/yt-dlp"
rm -f "$tmp/ytdlp.pid" "$tmp/ytdlp.kid"
PATH="$sleepbin:$PATH" bash "$script" download "https://example.com/v" auto >/dev/null 2>&1 &
pid=$!
await "$tmp/ytdlp.pid"
at=$SECONDS
kill -TERM "$pid"
rc=0
wait "$pid" || rc=$?
[[ $rc -eq 143 ]] || fail "a cancelled download must exit 143 (rc=$rc)"
prompt "$at" || fail "the cancel trap waited for the download instead of firing"
if alive "$(cat "$tmp/ytdlp.pid" 2>/dev/null)"; then fail "cancelling left yt-dlp running"; fi
if alive "$(cat "$tmp/ytdlp.kid" 2>/dev/null)"; then fail "cancelling left yt-dlp's child running"; fi

# the cobalt fetch phase: it runs behind a wait precisely so the trap can fire
# while a transfer is in flight
touch "$tmp/TUNNEL"
rm -f "$tmp/curl.pid"
bash "$script" download "https://example.com/v" auto >/dev/null 2>&1 &
pid=$!
await "$tmp/curl.pid"
at=$SECONDS
kill -TERM "$pid"
rc=0
wait "$pid" || rc=$?
[[ $rc -eq 143 ]] || fail "cancelling a fetch must exit 143 (rc=$rc)"
prompt "$at" || fail "a fetch in the foreground holds the cancel trap until curl is done"
if alive "$(cat "$tmp/curl.pid" 2>/dev/null)"; then fail "cancelling left the transfer running"; fi
rm -f "$tmp/TUNNEL"

# ---- a cancel takes the half-written file with it -----------------------------
# the two leaks a cancel leaves behind: a transfer that writes straight into the
# stash, and a yt-dlp run whose work dir and temp files outlive the RETURN trap
# that would normally have cleared them.

# cobalt: curl writes into the stash, so a cancel mid-transfer strands a partial
cstash="$tmp/stash.cancel"
mkdir -p "$cstash"
touch "$tmp/TUNNEL"
rm -f "$tmp/curl.pid"
STASH_DIR="$cstash" bash "$script" download "https://example.com/v" auto >/dev/null 2>&1 &
pid=$!
await "$tmp/curl.pid"
# the stub published its pid only after the bytes landed, so a non-empty stash
# here proves the leak this case is about rather than a passing accident
[[ -n "$(ls -A "$cstash")" ]] || fail "the transfer wrote nothing, so this cancel proves nothing"
at=$SECONDS
kill -TERM "$pid"
rc=0
wait "$pid" || rc=$?
[[ $rc -eq 143 ]] || fail "a cancelled transfer must exit 143 (rc=$rc)"
prompt "$at" || fail "the cancel trap waited for the transfer instead of firing"
left="$(ls -A "$cstash" 2>/dev/null)"
[[ -z "$left" ]] || fail "a cancelled transfer must leave no partial in the stash: $left"
rm -f "$tmp/TUNNEL"

# yt-dlp: TMPDIR is pointed at a dir of its own, so every mktemp the run makes
# (the work dir, its output log, its error log) is visible from outside
wdtmp="$tmp/work"
mkdir -p "$wdtmp"
ystash="$tmp/stash.ytdlp"
mkdir -p "$ystash"
rm -f "$tmp/ytdlp.pid" "$tmp/ytdlp.kid"
TMPDIR="$wdtmp" STASH_DIR="$ystash" PATH="$sleepbin:$PATH" \
  bash "$script" download "https://example.com/v" auto >/dev/null 2>&1 &
pid=$!
await "$tmp/ytdlp.pid"
at=$SECONDS
kill -TERM "$pid"
rc=0
wait "$pid" || rc=$?
[[ $rc -eq 143 ]] || fail "a cancelled yt-dlp download must exit 143 (rc=$rc)"
prompt "$at" || fail "the cancel trap waited for the download instead of firing"
left="$(ls -A "$wdtmp" 2>/dev/null)"
[[ -z "$left" ]] || fail "a cancelled yt-dlp download must leave no work dir or temp file: $left"
left="$(ls -A "$ystash" 2>/dev/null)"
[[ -z "$left" ]] || fail "a cancelled yt-dlp download must leave nothing in the stash: $left"
if alive "$(cat "$tmp/ytdlp.kid" 2>/dev/null)"; then fail "cancelling left yt-dlp's child running"; fi

# the other half of the rule: once a file has been announced as SAVED it is the
# user's, and a cancel arriving after that point must not take it away. the stub
# holds the foreground only briefly, because bash runs a pending trap at its next
# prompt rather than in the middle of a running child.
nstub="$tmp/notifybin"
mkdir -p "$nstub"
cat >"$nstub/notify-send" <<EOF
#!/bin/sh
echo \$\$ >"$tmp/notify.pid"
sleep 2
EOF
chmod +x "$nstub/notify-send"
dstash="$tmp/stash.done"
mkdir -p "$dstash"
rm -f "$tmp/notify.pid"
PATH="$nstub:$PATH" STASH_DIR="$dstash" \
  bash "$script" download "https://example.com/v" auto >"$tmp/done.out" 2>/dev/null &
pid=$!
# notify-send runs after SAVED, so its pid file is the cue that the download is
# finished and the script is still alive to be cancelled
await "$tmp/notify.pid"
at=$SECONDS
kill -TERM "$pid"
rc=0
wait "$pid" || rc=$?
[[ $rc -eq 143 ]] || fail "a cancel after SAVED must still exit 143 (rc=$rc)"
prompt "$at" || fail "the trap waited for notify-send instead of firing"
grep -q '^SAVED' "$tmp/done.out" || fail "the file should have been saved before the cancel"
kept="$(ls -A "$dstash" 2>/dev/null)"
[[ -n "$kept" ]] || fail "a cancel after SAVED must leave the finished file alone"
if alive "$(cat "$tmp/notify.pid" 2>/dev/null)"; then fail "cancelling left notify-send running"; fi

echo "stash-probe: all checks passed"
