"""Server health for the Protocol 47 admin dashboard (standard library only).

- parse_game_journal(): turns the game service's journal (journalctl -o json)
  into lifecycle events (start/stop/crash/restart) and grouped script/engine
  errors with their GDScript backtraces.
- HostSampler: CPU and memory of the game process (/proc/<pid>), and the
  droplet's load, memory, disk and network throughput.
- service_state(): systemd's view of the game service.
"""
import hashlib
import json
import os
import re
import subprocess
import time

SCRIPT_ERROR = re.compile(r"^(SCRIPT ERROR|ERROR|WARNING): (.*)$")
AT_LINE = re.compile(r"^\s+at: (.*)$")
BACKTRACE_LINE = re.compile(r"^\s+\[\d+\] (.*)$")


def _message(entry):
    message = entry.get("MESSAGE", "")
    if isinstance(message, list):  # journald encodes non-UTF-8 messages as byte arrays
        message = bytes(message).decode("utf-8", "replace")
    return str(message)


def _timestamp(entry):
    return int(entry.get("__REALTIME_TIMESTAMP", "0")) / 1_000_000


def lifecycle_kind(message):
    """systemd's own lines about the unit -> (kind, detail) or None."""
    if message.startswith("Started "):
        return "start", ""
    if message.startswith("Stopping ") or message.startswith("Stopped "):
        return "stop", ""
    if "Main process exited" in message and ("code=dumped" in message or "code=killed" in message):
        return "crash", message.split("Main process exited, ", 1)[-1]
    if "Main process exited" in message and "status=0/SUCCESS" not in message:
        return "exit", message.split("Main process exited, ", 1)[-1]
    if "Scheduled restart job" in message:
        return "restart", ""
    return None


def fingerprint(kind, message, location):
    # Numbers vary between occurrences (ids, counts); group without them.
    normalized = re.sub(r"\d+", "#", f"{kind}|{message}|{location}")
    return hashlib.sha1(normalized.encode()).hexdigest()[:16]


def parse_game_journal(entries):
    """Yields ("lifecycle", {...}) and ("error", {...}) records in order."""
    pending = None

    def flush():
        nonlocal pending
        if pending is not None:
            record = pending
            pending = None
            record["fingerprint"] = fingerprint(record["kind"], record["message"], record["location"])
            record["backtrace"] = "\n".join(record["backtrace"])
            return record
        return None

    for entry in entries:
        message = _message(entry)
        ts = _timestamp(entry)
        source = entry.get("SYSLOG_IDENTIFIER") or entry.get("_COMM") or ""
        if source == "systemd":
            done = flush()
            if done:
                yield "error", done
            lifecycle = lifecycle_kind(message)
            if lifecycle:
                yield "lifecycle", {"ts": ts, "kind": lifecycle[0], "detail": lifecycle[1]}
            continue
        started = SCRIPT_ERROR.match(message)
        if started:
            done = flush()
            if done:
                yield "error", done
            kind = {"SCRIPT ERROR": "script", "ERROR": "engine", "WARNING": "warning"}[started.group(1)]
            pending = {"ts": ts, "kind": kind, "message": started.group(2).strip(), "location": "", "backtrace": []}
            continue
        if pending is not None:
            at = AT_LINE.match(message)
            frame = BACKTRACE_LINE.match(message)
            if at and not pending["location"]:
                pending["location"] = at.group(1).strip()
                continue
            if frame:
                pending["backtrace"].append(frame.group(1).strip())
                continue
            if message.strip().startswith("GDScript backtrace"):
                continue
            done = flush()
            if done:
                yield "error", done
    done = flush()
    if done:
        yield "error", done


def read_game_journal(after_cursor="", since=None, unit="protocol47"):
    """(entries, last_cursor) from journalctl in JSON form."""
    command = ["journalctl", "-u", unit, "-o", "json", "--no-pager"]
    if after_cursor:
        command.append(f"--after-cursor={after_cursor}")
    elif since is not None:
        command.append(f"--since=@{int(since)}")
    try:
        output = subprocess.run(command, capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return [], after_cursor
    entries = []
    cursor = after_cursor
    for line in output.splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        entries.append(entry)
        cursor = entry.get("__CURSOR", cursor)
    return entries, cursor


def service_state(unit="protocol47", proc_root="/proc"):
    """systemd's view of the game service, with uptime in seconds."""
    properties = ["MainPID", "ActiveState", "SubState", "ActiveEnterTimestamp",
                  "ActiveEnterTimestampMonotonic", "NRestarts"]
    try:
        output = subprocess.run(["systemctl", "show", unit, *[f"-p{p}" for p in properties]],
                                capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    raw = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
    state = {"MainPID": int(raw.get("MainPID") or 0), "NRestarts": int(raw.get("NRestarts") or 0),
             "ActiveState": raw.get("ActiveState", ""), "SubState": raw.get("SubState", ""),
             "ActiveEnterTimestamp": raw.get("ActiveEnterTimestamp", ""), "uptime": None}
    entered = int(raw.get("ActiveEnterTimestampMonotonic") or 0)
    try:
        with open(os.path.join(proc_root, "uptime")) as handle:
            boot_seconds = float(handle.read().split()[0])
        if entered and state["ActiveState"] == "active":
            state["uptime"] = max(0.0, boot_seconds - entered / 1_000_000)
    except (OSError, ValueError, IndexError):
        pass
    return state


class HostSampler:
    """Rates need two readings, so each sample() compares with the last one."""

    def __init__(self, proc_root="/proc", disk_path="/"):
        self.proc = proc_root
        self.disk_path = disk_path
        self.clock_ticks = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100
        self._last = None

    def _read(self, *parts):
        try:
            with open(os.path.join(self.proc, *parts)) as handle:
                return handle.read()
        except OSError:
            return ""

    def process(self, pid):
        if not pid:
            return {}
        stat = self._read(str(pid), "stat")
        status = self._read(str(pid), "status")
        if not stat:
            return {}
        # Fields after the "(comm)" name: utime is field 14, stime field 15.
        fields = stat.rsplit(")", 1)[-1].split()
        cpu_ticks = int(fields[11]) + int(fields[12])
        rss = re.search(r"VmRSS:\s+(\d+) kB", status)
        threads = re.search(r"Threads:\s+(\d+)", status)
        return {"cpu_ticks": cpu_ticks, "rss_mb": int(rss.group(1)) / 1024 if rss else 0.0,
                "threads": int(threads.group(1)) if threads else 0}

    def host(self):
        loadavg = self._read("loadavg").split()
        meminfo = dict(re.findall(r"^(\w+):\s+(\d+)", self._read("meminfo"), re.M))
        total = int(meminfo.get("MemTotal", 0))
        available = int(meminfo.get("MemAvailable", 0))
        rx = tx = 0
        for line in self._read("net", "dev").splitlines()[2:]:
            name, _, data = line.partition(":")
            if name.strip() in ("lo", "") or not data:
                continue
            values = data.split()
            rx += int(values[0])
            tx += int(values[8])
        try:
            disk = os.statvfs(self.disk_path)
            disk_pct = 100.0 * (1 - disk.f_bavail / disk.f_blocks) if disk.f_blocks else 0.0
        except OSError:
            disk_pct = 0.0
        return {"load1": float(loadavg[0]) if loadavg else 0.0,
                "mem_used_pct": 100.0 * (total - available) / total if total else 0.0,
                "mem_total_mb": total / 1024, "disk_used_pct": disk_pct, "rx": rx, "tx": tx,
                "cpus": os.cpu_count() or 1}

    def sample(self, pid, now=None):
        now = time.time() if now is None else now
        process = self.process(pid)
        host = self.host()
        sample = {"ts": now, "pid": pid, "rss_mb": process.get("rss_mb", 0.0), "threads": process.get("threads", 0),
                  "load1": host["load1"], "mem_used_pct": host["mem_used_pct"], "mem_total_mb": host["mem_total_mb"],
                  "disk_used_pct": host["disk_used_pct"], "cpu_pct": None, "net_in_kbps": None, "net_out_kbps": None}
        last = self._last
        if last and now > last["ts"]:
            elapsed = now - last["ts"]
            if process and last.get("pid") == pid and "cpu_ticks" in last:
                # Percent of one core, like top.
                sample["cpu_pct"] = 100.0 * (process["cpu_ticks"] - last["cpu_ticks"]) / self.clock_ticks / elapsed
            sample["net_in_kbps"] = max(0.0, (host["rx"] - last["rx"]) * 8 / 1000 / elapsed)
            sample["net_out_kbps"] = max(0.0, (host["tx"] - last["tx"]) * 8 / 1000 / elapsed)
        self._last = {"ts": now, "pid": pid, "rx": host["rx"], "tx": host["tx"], **process}
        return sample
