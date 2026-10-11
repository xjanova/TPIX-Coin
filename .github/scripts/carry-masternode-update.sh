#!/usr/bin/env bash
#
# แนบไฟล์อัปเดตของ TPIX Master Node ไปกับ release ของวอลเล็ต
#
# ทำไมต้องมี
#   แอป Master Node รุ่น <= 1.13.13 (บิลด์จาก masternode-ui ที่เคยอยู่ใน repo นี้)
#   ใช้ electron-updater แบบ github ที่อ่าน "latest release" ของ repo นี้เสมอ
#   release ล่าสุดเป็นของวอลเล็ต → ถ้าไม่มี latest.yml แอปเก่าเด้ง 404
#
# แหล่งไฟล์
#   1. ฟีดสาธารณะ https://tpix.online/updates/masternode — ตัวเดียวกับที่แอป 1.14.0 ขึ้นไปอ่าน
#      (เว็บดึงรุ่นล่าสุดจาก repo TPIX-Masternode ที่เป็นไพรเวทให้ GITHUB_TOKEN ของที่นี่อ่านไม่ได้)
#   2. ถอยไปคัดลอกจาก release ก่อนหน้าของ repo นี้แบบเดิม — เมื่อฟีดล่ม/ไฟล์ไม่ผ่านการตรวจ/
#      รุ่นในฟีดเก่ากว่าที่เคยแนบ (ไม่ทำให้แย่ลงกว่าเดิม)
#
#   เดิมใช้แต่ข้อ 2 → ไฟล์ค้างที่ 1.14.0 (2026-08-23) ทุก release เครื่องเก่าต้องกระโดดสองทอด
#   ≤1.13.13 → 1.14.0 → รุ่นปัจจุบัน และระหว่างทางได้รัน 1.14.0 ที่ genesis ผิด + gRPC เปิด 0.0.0.0
#
# ใช้
#   carry-masternode-update.sh <new-tag>            ดาวน์โหลด ตรวจ แล้วอัปโหลดเข้า release <new-tag>
#   carry-masternode-update.sh <new-tag> --dry-run  ดาวน์โหลด + ตรวจอย่างเดียว ไม่แตะ GitHub (ทดสอบในเครื่อง)
#
# ต้องมี: curl, openssl, base64, sort -V, gh (เฉพาะตอนไม่ใช่ dry-run) + GH_TOKEN, GITHUB_REPOSITORY

set -euo pipefail

NEW_TAG="${1:?usage: carry-masternode-update.sh <new-tag> [--dry-run]}"
DRY_RUN="${2:-}"
MN_FEED="${MN_FEED:-https://tpix.online/updates/masternode}"
WORK_DIR="${WORK_DIR:-mn-update}"
# ⚠️ ห้ามลบ UA — WAF ของ tpix.online ตอบ 403 ให้คำขอที่ไม่มี User-Agent
UA="TPIX-Coin-CI (+https://github.com/${GITHUB_REPOSITORY:-xjanova/TPIX-Coin})"
NAME_RE='^TPIX-Master-Node-Setup-[0-9]+\.[0-9]+\.[0-9]+\.exe$'

log() { echo "$*" >&2; }

# ค่าบรรทัดบนสุดของ key ใน latest.yml (ระดับบนสุด ไม่ใช่ใต้ files:)
yml_top() { sed -n "s/^$1: *//p" "$2" | head -1 | tr -d "'\"\r "; }

# ตรวจชุดไฟล์ในโฟลเดอร์ปัจจุบัน: latest.yml + ตัวติดตั้งที่มันอ้างถึง ต้องตรงกันทุกอย่าง
# พิมพ์ "<version> <file>" เมื่อผ่าน
verify_set() {
    local ver file sha size got_sha got_size
    [ -s latest.yml ] || { log "ไม่มี latest.yml"; return 1; }
    ver=$(yml_top version latest.yml)
    file=$(yml_top path latest.yml)
    sha=$(yml_top sha512 latest.yml)
    size=$(sed -n 's/^ *size: *//p' latest.yml | head -1 | tr -d "'\"\r ")
    [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { log "version ใน latest.yml ผิดรูป: $ver"; return 1; }
    # ต้องเป็นตัวติดตั้ง Master Node ของรุ่นนั้นเท่านั้น — กันฟีดเพี้ยนพาไฟล์อื่น/พาธแปลกเข้ามา
    [[ "$file" =~ $NAME_RE ]] || { log "ชื่อไฟล์ใน latest.yml ไม่ใช่ตัวติดตั้ง Master Node: $file"; return 1; }
    [ "$file" = "TPIX-Master-Node-Setup-${ver}.exe" ] || { log "ชื่อไฟล์ไม่ตรงกับ version: $file / $ver"; return 1; }
    [ -s "$file" ] || { log "ไม่มีไฟล์ $file"; return 1; }
    [ "$(head -c 2 "$file")" = "MZ" ] || { log "$file ไม่ใช่ไฟล์ .exe (ไม่ขึ้นต้นด้วย MZ)"; return 1; }
    got_size=$(wc -c < "$file" | tr -d ' ')
    [ -z "$size" ] || [ "$got_size" = "$size" ] || { log "ขนาด $file ไม่ตรง: $got_size / $size"; return 1; }
    # electron-updater ตรวจ sha512 นี้อีกชั้นตอนติดตั้ง — ไม่ตรงตั้งแต่ตรงนี้ = แนบไปก็ติดตั้งไม่ได้
    got_sha=$(openssl dgst -sha512 -binary "$file" | base64 | tr -d '\n')
    [ "$got_sha" = "$sha" ] || { log "sha512 ของ $file ไม่ตรงกับ latest.yml"; return 1; }
    echo "$ver $file"
}

# ดึงชุดล่าสุดจากฟีดสาธารณะ
from_feed() {
    local file
    curl -fsSL --proto '=https' --tlsv1.2 -A "$UA" --max-time 60 "$MN_FEED/latest.yml" -o latest.yml || return 1
    file=$(yml_top path latest.yml)
    [[ "$file" =~ $NAME_RE ]] || { log "ฟีดตอบชื่อไฟล์แปลก: $file"; return 1; }
    # ฟีด redirect ไปที่เก็บไฟล์ของ GitHub — ยอมเฉพาะปลายทาง https
    curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 -A "$UA" --max-time 900 \
        "$MN_FEED/$file" -o "$file" || return 1
    # blockmap มีไว้ดาวน์โหลดเฉพาะส่วนต่าง ไม่มีก็ได้ (แอปจะโหลดเต็มไฟล์แทน)
    curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 -A "$UA" --max-time 120 \
        "$MN_FEED/$file.blockmap" -o "$file.blockmap" || rm -f "$file.blockmap"
    verify_set
}

# ชุดที่แนบไว้กับ release ก่อนหน้าของ repo นี้ (ทางเดิม)
from_previous_release() {
    local src
    src=$(gh api "repos/${GITHUB_REPOSITORY}/releases?per_page=100" --jq \
        "[ .[]
           | select(.draft == false and .prerelease == false)
           | select(.tag_name != \"${NEW_TAG}\")
           | select([.assets[].name] | index(\"latest.yml\"))
           | .tag_name ][0] // empty")
    [ -n "$src" ] || return 1
    log "release ก่อนหน้าที่มี latest.yml: $src"
    gh release download "$src" --pattern 'latest.yml' --pattern 'TPIX-Master-Node-Setup-*' --clobber || return 1
    verify_set
}

# version ที่ release ก่อนหน้าแนบไว้ — ใช้กันฟีดพาไปรุ่นที่เก่ากว่า (ว่าง = ไม่รู้)
previous_version() {
    local src
    src=$(gh api "repos/${GITHUB_REPOSITORY}/releases?per_page=100" --jq \
        "[ .[]
           | select(.draft == false and .prerelease == false)
           | select(.tag_name != \"${NEW_TAG}\")
           | select([.assets[].name] | index(\"latest.yml\"))
           | .tag_name ][0] // empty") || return 0
    [ -n "$src" ] || return 0
    gh release download "$src" --pattern 'latest.yml' --output - 2>/dev/null \
        | sed -n 's/^version: *//p' | head -1 | tr -d "'\"\r " || true
}

rm -rf "$WORK_DIR" && mkdir -p "$WORK_DIR" && cd "$WORK_DIR"

result=""
if result=$(from_feed); then
    log "ฟีด tpix.online: Master Node ${result%% *} ผ่านการตรวจ"
    if [ "$DRY_RUN" != "--dry-run" ]; then
        prev=$(previous_version)
        # รุ่นในฟีดต้องไม่เก่ากว่าที่เคยแนบ (เครื่องผู้ใช้ตั้ง allowDowngrade = false อยู่แล้ว แต่กันไว้อีกชั้น)
        if [ -n "$prev" ] && [ "$(printf '%s\n%s\n' "$prev" "${result%% *}" | sort -V | tail -1)" != "${result%% *}" ]; then
            log "::warning::ฟีดให้ ${result%% *} เก่ากว่าที่เคยแนบ ($prev) — ใช้ชุดจาก release ก่อนหน้าแทน"
            result=""
        fi
    fi
else
    log "::warning::ดึง/ตรวจไฟล์จากฟีด ${MN_FEED} ไม่ผ่าน — ถอยไปใช้ชุดจาก release ก่อนหน้า"
    result=""
fi

if [ "$DRY_RUN" = "--dry-run" ]; then
    [ -n "$result" ] || { log "dry-run: ฟีดไม่ผ่าน"; exit 1; }
    log "dry-run: จะอัปโหลด latest.yml + ${result#* }$( [ -f "${result#* }.blockmap" ] && echo ' + blockmap') เข้า $NEW_TAG"
    exit 0
fi

if [ -z "$result" ]; then
    rm -f latest.yml TPIX-Master-Node-Setup-*
    if ! result=$(from_previous_release); then
        log "ไม่พบชุดอัปเดต Master Node ที่ใช้ได้ — ข้ามขั้นตอนนี้"
        exit 0
    fi
fi

file="${result#* }"
assets=(latest.yml "$file")
[ -f "$file.blockmap" ] && assets+=("$file.blockmap")
# latest.yml ต้องอยู่ release เดียวกับ .exe ที่มันอ้างถึง
# ไม่งั้น URL ที่ electron-updater ประกอบขึ้นจะชี้ผิด release แล้ว 404
gh release upload "$NEW_TAG" "${assets[@]}" --clobber
log "แนบ Master Node ${result%% *} เข้า $NEW_TAG แล้ว — แอปรุ่นเก่าอัปเดตตรงมารุ่นนี้ได้ทันที"
