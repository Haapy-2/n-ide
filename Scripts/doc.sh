#!/bin/bash
# 큰 문서를 통째로 읽지 않고 장 하나만 본다(토큰 절약).
#   Scripts/doc.sh PLAN        장 목록(줄 수 포함)
#   Scripts/doc.sh PLAN 19     "## 19." 장만 출력
# 문서 이름은 docs/ 안 파일 이름(확장자 빼고, 대소문자 그대로).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
name="${1:?문서 이름을 주세요 (예: PLAN)}"
file="$ROOT/docs/$name.md"
[ -f "$file" ] || { echo "✗ docs/$name.md 가 없습니다"; exit 1; }
if [ $# -lt 2 ]; then
  awk '/^## /{if(t)printf "%4d줄  %s\n",NR-s,t; t=$0; s=NR} END{if(t)printf "%4d줄  %s\n",NR-s+1,t}' "$file"
  exit 0
fi
out=$(awk -v n="$2" '/^## /{on = (index($0, "## " n ".") == 1 || $0 == "## " n)} on' "$file")
[ -n "$out" ] || { echo "✗ docs/$name.md 에 \"## $2.\" 장이 없습니다"; exit 1; }
echo "$out"
