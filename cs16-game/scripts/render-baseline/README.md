# Native render environment control

Run from the repository root, with no simultaneous builds or benchmarks:

```sh
godot --audio-driver Dummy --always-on-top --path scripts/render-baseline \
  --script res://probe.gd --log-file /tmp/protocol47-render-baseline.log -- \
  --seconds=95 --report=/tmp/protocol47-render-baseline.json
```

This separate project renders one rotating unshaded box at 1280×720, with the
same uncapped Compatibility mode used by the live-match benchmark. It loads
no game code, assets, autoloads, or player settings. Audio must be Dummy.
Startup warmup is excluded. The report includes actual draw coverage and every
frame interval over 25 ms, with elapsed timestamps to investigate periodicity.
Timing collection does not print progress or perform file I/O. Durations are
bounded to 60–180 seconds so a 30-second periodic hitch can recur.

`RENDER_BASELINE_COLLECTED` means collection completed, not that gameplay is
smooth. A hitch here can exclude game callbacks as a necessary cause; it cannot
by itself distinguish engine, driver, OS, and other host applications. A clean
run does not prove that game code caused a hitch observed in another run.
Renderer/driver overrides can be supplied with the standard Godot flags.

`--vsync=enabled` selects a frame-pacing comparison with the game's default
VSync setting; `--vsync=disabled` is the unchanged uncapped default. The report
records the requested setting and engine-reported mode. Run these serially,
using separate report/log paths, and compare slow-interval timestamps as well
as percentiles. VSync waiting is included in frame intervals; this comparison
does not substitute for measuring the actual game or prove display/input latency.
Pass `--instrumented` whenever attaching a profiler or collecting additional
diagnostics during the run. It marks the report so traced results cannot be
mistaken for clean controls. The flag does not attach any profiler itself.
