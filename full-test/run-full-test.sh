#!/usr/bin/env bash
cd /home/connor/CursiveOS
LOGFILE="logs/cursiveos-full-test-$(date +%Y%m%d-%H%M%S).log"
echo "LOG=$LOGFILE"
bash cursiveos-full-test-v1.4.sh > "$LOGFILE" 2>&1 &
BGPID=$!
echo "PID=$BGPID"
echo "$BGPID $LOGFILE" > /tmp/tao-fulltest-run.txt
wait $BGPID
echo "EXIT=$?"
