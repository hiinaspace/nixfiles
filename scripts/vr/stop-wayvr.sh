if [ -z "${MAINPID:-}" ] || ! kill -0 "$MAINPID" 2>/dev/null; then
  exit 0
fi

kill -TERM "$MAINPID"
for _ in $(seq 1 50); do
  if ! kill -0 "$MAINPID" 2>/dev/null; then
    exit 0
  fi
  sleep 0.1
done

echo "WayVR did not finish teardown after 5 seconds; using SIGKILL" >&2
kill -KILL "$MAINPID" 2>/dev/null || true
