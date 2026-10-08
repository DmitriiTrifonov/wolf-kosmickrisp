#!/bin/sh
out="$1"; : > "$out"; end=$(( $(date +%s) + 1500 ))
while [ $(date +%s) -lt $end ]; do
  p=$(ps ax -o pid,command | grep 'WolfNewOrder_x64.exe' | grep -v 'grep\|/bin/sh' | awk '{print $1}' | tail -1)
  if [ -n "$p" ]; then
    g=$(footprint $p 2>/dev/null | grep -E 'IOAccelerator \(graphics\)' | awk '{print $1$2}')
    h=$(grep -a 'kkbridge2' "$HOME/Library/Application Support/notproton/launchers/201810/notproton-wine.log" 2>/dev/null | tail -1 | grep -oE ' 12=[0-9]+')
    echo "$(date +%H:%M:%S) gpu=$g counterheaps=$h swap=$(sysctl -n vm.swapusage | awk '{print $6}')" >> "$out"
  fi
  sleep 15
done
