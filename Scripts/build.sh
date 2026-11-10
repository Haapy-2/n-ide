#!/bin/bash
# 빌드: 앱을 build/DerivedData에 빌드한다. CONFIG=Release Scripts/build.sh 처럼 구성을 바꿀 수 있다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
xb build "빌드(${CONFIG:-Debug})" -scheme NovelEditor -configuration "${CONFIG:-Debug}" build
