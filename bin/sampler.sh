#!/bin/sh
out="$1"; : > "$out"
end=$(( $(date +%s) + 300 ))
while [ $(date +%s) -lt $end ]; do
  p=$(ps ax -o pid,command | grep 'WolfNewOrder_x64.exe' | grep -v 'grep\|/bin/sh' | awk '{print $1}' | tail -1)
  if [ -n "$p" ]; then echo "$(date +%s) $(vmmap -w $p 2>/dev/null | grep -cE '^IOAccelerator \(graphics\)')" >> "$out"; fi
  sleep 3
done
