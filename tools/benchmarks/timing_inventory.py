"""Inventory logged timing maxima without inventing timings from means or counters.

Each reported maximum carries its exact field, units, source line and coverage.
Window maxima keep their latest value and the largest *reported* window maximum.
Scopes overlap; this inventory is neither a CPU partition nor a dependency graph.
"""
import re

SCALE = {"ns": 1e-6, "us": 1e-3, "ms": 1.0}
MAXIMUM = re.compile(r"\b(\w*max\w*_(ns|us|ms))=(\d+(?:\.\d+)?)\b")


def scope(line):
    text = re.sub(r"^(?:info|warn|warning|error)(?:\([^)]*\))?:\s*", "", line)
    text = re.sub(r"^macho-processor:\s*", "", text)
    marker = text.split(":", 1)[0]
    # Busiest rank can change between snapshots; name, not rank, is identity.
    keys = re.findall(r"\b(?:stage|name|import|op|slot|scope|key|kind)=(?:'[^']*'|\S+)", text)
    return marker + (" / " + " / ".join(keys) if keys else "")


def parse(lines, ticks_per_ms=None):
    maxima, estimates, cpu, limits, unconverted = {}, {}, {}, {}, {}
    for number, line in enumerate(lines, 1):
        identity = scope(line)
        for match in re.finditer(r"\b(\w*max\w*_ticks)=(\d+)\b", line):
            tick_row = dict(label=identity, field=match[1], ticks=int(match[2]), line=number,
                raw=line, coverage="guest clock ticks; not host CPU ms")
            if ticks_per_ms and identity.startswith(("PE64 WAIT COST", "PE64 WAIT FINDINGS", "PE64 WAIT ESCALATION")):
                key = (identity, match[1])
                value = int(match[2]) / ticks_per_ms
                prior = maxima.get(key)
                maxima[key] = dict(**tick_row, max_ms=value,
                    peak_reported_ms=max(value, prior["peak_reported_ms"] if prior else value),
                    basis="guest elapsed")
            else:
                unconverted[(identity, match[1])] = tick_row
        for match in MAXIMUM.finditer(line):
            field, unit, value = match.groups()
            value = float(value) * SCALE[unit]
            key = (identity, field)
            if field.startswith("requested_"):
                limits[key] = dict(label=identity, field=field, limit_ms=value, line=number, raw=line)
                continue
            prior = maxima.get(key)
            if field.startswith("sampled_") and "max" in field:
                coverage = "timed samples only"
            elif "CADENCE" in line or "HUD RATE" in line:
                coverage = "reported recent window"
            else:
                coverage = "logged scope; elapsed may include waits"
            basis = "thread CPU" if identity.startswith(("VULKAN FSI OBSERVER HOST CPU", "VULKAN PIPELINE NATIVE CALL")) and "_cpu_" in field else "elapsed"
            if identity.startswith("VULKAN PIPELINE NATIVE CALL"):
                coverage = "one reported native call with elapsed >=50ms; other calls unreported"
            maxima[key] = dict(label=identity, field=field, max_ms=value,
                               peak_reported_ms=max(value, prior["peak_reported_ms"] if prior else value),
                               line=number, raw=line, coverage=coverage, basis=basis)
        # Counters may encode named statistics inside a slash-separated tuple.
        for label, keys, values in re.findall(r"(\w+)\(([^)]+)\)=([0-9./]+)", line):
            keys, values = keys.split("/"), values.split("/")
            if len(keys) != len(values):
                continue
            for statistic, value in zip(keys, values):
                if "max" not in statistic:
                    continue
                unit = re.search(r"(?:^|_)(ns|us|ms)(?:_|$)", statistic + "_" + label)
                if not unit:
                    continue
                value = float(value) * SCALE[unit[1]]
                field = label + "." + statistic
                key = (identity, field)
                prior = maxima.get(key)
                coverage = "logged elapsed statistic; includes scheduling/waits"
                if label == "completion_ms_per_group":
                    coverage = "submit-to-fence observation upper bound; not GPU execution"
                maxima[key] = dict(label=identity, field=field, max_ms=value,
                                   peak_reported_ms=max(value, prior["peak_reported_ms"] if prior else value),
                                   line=number, raw=line, coverage=coverage, basis="elapsed",
                                   total_ms=float(values[keys.index("total")]) * SCALE[unit[1]] if "total" in keys else None)
        if "PE64 IMPORT HISTOGRAM:" in line:
            match = re.search(r"import=(\S+) calls=(\d+).*mean_ns=(\d+) estimated_ms=(\d+)", line)
            if match:
                estimates["Import / " + match[1]] = dict(label="Import / " + match[1], basis="sampled estimate",
                    calls=int(match[2]), total_ms=float(match[4]), line=number, max_ms=None, raw=line,
                    coverage="maximum absent from this log")
        if "FALLBACK OPS:" in line:
            prefix = "Workers fallback / " if "WORKER" in line else "Owner fallback / "
            for match in re.finditer(r"(\w+)=(\d+)\([^)]*?estimated_ns=(\d+),samples=(\d+)[^)]*\)", line):
                label = prefix + match[1]
                estimates[label] = dict(label=label, basis="sampled estimate", calls=int(match[2]),
                    total_ms=int(match[3]) / 1e6 if int(match[4]) else None, line=number, max_ms=None,
                    raw=line, coverage="maximum absent from this log")
        if "PE64 IMPORT TIMING:" in line or "PE64 FALLBACK TIMING:" in line:
            values = dict(re.findall(r"\b(\w+)=(\d+)", line))
            samples = int(values["samples"])
            label = identity
            estimates[label] = dict(label=label, basis="sampled estimate", calls=int(values["calls"]),
                total_ms=int(values["sampled_ns"]) * int(values["calls"]) / samples / 1e6 if samples else None,
                line=number, max_ms=int(values["sampled_max_ns"]) / 1e6 if samples else None,
                raw=line, coverage="timed samples only; no samples means unknown")
        if "PE64 WORKER HOST CPU:" in line:
            match = re.search(r"slot=(\d+).*name='([^']*)' cpu_us=(\d+) elapsed_us=(\d+)", line)
            if match:
                cpu[match[1]] = dict(label=match[2], slot=int(match[1]), total_ms=int(match[3]) / 1000,
                    elapsed_ms=int(match[4]) / 1000, line=number, raw=line, basis="thread CPU",
                    max_ms=None, coverage="cumulative thread CPU; per-operation maximum unmeasured")
    # A zero-sample maximum is not evidence that the scope is fast.
    for row in maxima.values():
        if row["field"].startswith("sampled_") and "max" in row["field"] and re.search(r"\bsamples=0\b", row["raw"]):
            row["max_ms"] = row["peak_reported_ms"] = None
            row["coverage"] = "no timed samples; maximum unknown"
    for row in maxima.values():
        vals = dict(re.findall(r"\b(\w+)=(\d+(?:\.\d+)?)", row["raw"]))
        row["calls"] = int(vals["calls"]) if "calls" in vals else None
        row["total_ms"] = next((float(vals[key]) * scale for key, scale in
            (("total_us", .001), ("total_ms", 1), ("host_ms", 1), ("worker_us", .001), ("room_wait_ms", 1), ("wait_ms", 1)) if key in vals), row.get("total_ms"))
        if row["label"].startswith("VULKAN FSI OBSERVER HOST CPU"):
            total = "sampled_cpu_ns" if row["basis"] == "thread CPU" else "sampled_elapsed_ns"
            row["total_ms"] = float(vals[total]) / 1e6 if total in vals else None
        if row["basis"] == "guest elapsed" and ticks_per_ms and "total_ticks" in vals:
            row["total_ms"] = int(vals["total_ticks"]) / ticks_per_ms
        if vals.get("calls") == "0" or vals.get("waits") == "0":
            row["max_ms"] = row["peak_reported_ms"] = None
            row["coverage"] = "no timed calls/waits; maximum unknown"
    # The complete timing ledger and ranked summary describe the same named
    # operation. Keep the newer detailed row; preserve superseded evidence.
    # Names are the best available identity, not an import-entry identifier.
    def alias(raw):
        if "PE64 IMPORT TIMING:" in raw or "PE64 IMPORT HISTOGRAM:" in raw:
            match = re.search(r"\bimport=(\S+)", raw)
            return "Import / " + match[1] if match else None
        if "PE64 FALLBACK TIMING:" in raw:
            match = re.search(r"\bop=(\S+)", raw)
            return ("Workers fallback / " if "scope='WORKER " in raw else "Owner fallback / ") + match[1] if match else None
        return None
    detailed = {alias(row["raw"]): row for row in estimates.values()
                if " TIMING:" in row["raw"] and alias(row["raw"]) is not None}
    aliases = []
    for key, row in list(estimates.items()):
        full = detailed.get(key)
        if full and full["line"] >= row["line"]:
            aliases.append(dict(kind="estimate", summary=row, detailed_line=full["line"]))
            del estimates[key]
    detailed_maxima = {(alias(row["raw"]), row["field"]): row for row in maxima.values()
                       if "PE64 IMPORT TIMING:" in row["raw"]}
    for key, row in list(maxima.items()):
        if "PE64 IMPORT HISTOGRAM:" not in row["raw"]:
            continue
        full = detailed_maxima.get((alias(row["raw"]), row["field"]))
        if full and full["line"] >= row["line"]:
            if row["peak_reported_ms"] is not None:
                full["peak_reported_ms"] = max(full["peak_reported_ms"] or 0, row["peak_reported_ms"])
            aliases.append(dict(kind="maximum", summary=row, detailed_line=full["line"]))
            del maxima[key]
    return dict(maxima=list(maxima.values()), estimates=list(estimates.values()), cpu=list(cpu.values()), limits=list(limits.values()), unconverted=list(unconverted.values()), aliases=aliases)

