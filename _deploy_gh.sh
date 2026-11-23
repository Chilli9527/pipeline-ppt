#!/usr/bin/env bash
# 一鍵部署 decks/ 去 GitHub Pages，並且驗證線上真係換咗內容。
# 用法：./_deploy_gh.sh "commit message"
#       ./_deploy_gh.sh                 # 自動用時間做 commit message
# 環境變數：WAIT_SECS=300（等 Pages build 上限）
set -uo pipefail

REPO="Chilli9527/pipeline-ppt"
BRANCH="main"
BASE="https://chilli9527.github.io/pipeline-ppt/"
WAIT_SECS="${WAIT_SECS:-300}"
PUSH_TRIES=3

cd "$(dirname "$0")" || { echo "✗ 入唔到腳本目錄" >&2; exit 1; }

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
info() { printf '\033[36m▶\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v git  >/dev/null 2>&1 || die "搵唔到 git"
command -v curl >/dev/null 2>&1 || die "搵唔到 curl"
[ -d .git ] || die "呢個目錄唔係 git repo：$(pwd)"

MSG="${1:-decks: 自動部署 $(date '+%Y-%m-%d %H:%M')}"

# ---------- 1. commit ----------
if [ -n "$(git status --porcelain)" ]; then
  info "commit 改動"
  git add -A || die "git add 失敗"
  git -c user.name="金水" -c user.email="bot@local" commit -q -m "$MSG" || die "git commit 失敗"
  ok "$(git log -1 --pretty='%h %s')"
else
  info "冇新改動，跳過 commit"
fi

SHA="$(git rev-parse --short HEAD)"
FULL="$(git rev-parse HEAD)"

# ---------- 2. push ----------
info "push → $REPO / $BRANCH"
pushed=0
for i in $(seq 1 "$PUSH_TRIES"); do
  if git -c http.version=HTTP/1.1 push -q origin "$BRANCH" 2>/tmp/deploy_gh_push.err; then
    pushed=1; break
  fi
  warn "push 第 $i 次失敗：$(tr '\n' ' ' < /tmp/deploy_gh_push.err | cut -c1-160)"
  sleep $((i * 3))
done
[ "$pushed" = 1 ] || die "push 失敗 $PUSH_TRIES 次（網絡或衝突）。試 git pull --rebase origin $BRANCH 後再跑"
ok "push 完成 $SHA"

# ---------- 3. 等 Pages build ----------
info "等 GitHub Pages build（上限 ${WAIT_SECS}s）"
START=$(date +%s)
if command -v gh >/dev/null 2>&1; then
  while :; do
    line="$(gh api "repos/$REPO/pages/builds/latest" \
      --jq '"\(.status) \(.commit[0:7]) \(.updated_at)"' 2>/dev/null)"
    status="${line%% *}"
    commit="$(printf '%s' "$line" | awk '{print $2}')"
    case "$status" in
      built)
        if [ "$commit" = "$SHA" ]; then
          ok "build built（$commit · 完成 $(date '+%H:%M:%S')）"; break
        fi
        warn "build 完成但係舊 commit（${commit} ≠ ${SHA}），繼續等"
        ;;
      errored|failed)
        die "GitHub Pages build 失敗（commit ${commit}）→ 去 https://github.com/${REPO}/actions 睇 log" ;;
      "")
        warn "攞唔到 build 狀態，改用 HTTP 比對判斷" ;;
      *)
        printf '  · %s %s\r' "$status" "$(date '+%H:%M:%S')" ;;
    esac
    [ $(( $(date +%s) - START )) -ge "$WAIT_SECS" ] && die "等 Pages build 超時（${WAIT_SECS}s），狀態：${status:-unknown}"
    sleep 8
  done
else
  warn "冇 gh CLI，跳過 build 狀態，直接 HTTP 比對"
fi

# ---------- 4. 線上驗證：逐檔比 sha256 ----------
info "線上驗證：本地 vs 線上 sha256"
FILES="$(git ls-files '*.html' '*.md')"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
FAILS=0; N=0; BAD=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  N=$((N + 1))
  url="$BASE$f?cb=$(date +%s)${N}"
  curl -fsS --max-time 30 "$url" -o "$TMP" || die "拉唔到線上檔案：$url"
  a="$(shasum -a 256 "$f" | awk '{print $1}')"
  b="$(shasum -a 256 "$TMP" | awk '{print $1}')"
  if [ "$a" != "$b" ]; then
    FAILS=$((FAILS + 1)); BAD="$BAD
    - $f"
    warn "內容唔同：$f"
  fi
done <<< "$FILES"

[ "$FAILS" -eq 0 ] || die "線上驗證失敗：$FAILS / $N 個檔同本地唔一致，疑似 Page 未更新或檔案漏上：$BAD"
ok "$N / $N 個檔（html + md）同本地完全一致"

# ---------- 5. 紅線檢查 ----------
if grep -rIq "vercel\.app" --include='*.html' . 2>/dev/null; then
  warn "本地仍有 vercel.app 引用（Vercel 備份版會有，GitHub 版應該 0）："
  grep -rn "vercel\.app" --include='*.html' . | sed 's/^/    /'
else
  ok "無 vercel.app 寫死引用"
fi

info "完成 · $(date '+%Y-%m-%d %H:%M:%S')"
printf '  %s\n' "$BASE"
