#!/bin/bash
# 실행: 빌드한 뒤 앱을 연다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
"$ROOT/Scripts/build.sh"
open "$DERIVED/Build/Products/${CONFIG:-Debug}/NovelEditor.app"
