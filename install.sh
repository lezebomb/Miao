#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$project_root/pet/miaomiao"
codex_root="${CODEX_HOME:-$HOME/.codex}"
destination="$codex_root/pets/miaomiao"

test -f "$source_dir/pet.json"
test -f "$source_dir/spritesheet.webp"
mkdir -p "$destination"
cp "$source_dir/pet.json" "$destination/pet.json"
cp "$source_dir/spritesheet.webp" "$destination/spritesheet.webp"

echo "妙妙已安装到 $destination"
echo "请完全退出并重新打开 Codex，然后在宠物选择器中选择“妙妙”。"
