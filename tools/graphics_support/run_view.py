"""Rendering-relevant facts from one supplied run log, stated as observed and never as proof."""
import html


TESSELLATION_WARNING_FINDING = (
    "Traced to Rosette's CPU decode, not Vulkan: Xenia's VulkanPipelineCache::Initialize verifies its twelve tessellation handles with a vectorized sequence "
    "(vpcmpeqq/vpor/vpackssdw/vtestps, then vperm2f128 with a memory operand and vmovmskpd). The decoder dropped the base register of VPERM2F128 and VINSERTF128/VEXTRACTF128 memory operands, "
    "so [r13+0x168] was read as the absolute address 0x168, returned zeros, and the check reported a null handle. Replaying the exact bytes with all twelve handles set failed before the fix and passes after it "
    "(interpreted and translated), as do the memory forms of the lane instructions and a scan of every memory form in Xenia's image. This is a diagnosis from a replay, not from this log: "
    "a run of a rebuilt runner must not log the warning, and if it still does, this explanation is wrong."
)


def _int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _counts(text, expected=4):
    parts = str(text).split("/")
    return [_int(p) for p in parts] if len(parts) == expected else [0] * expected


def native_dispatch_total(run):
    """Total native texture dispatches recorded by the final cumulative counter line."""
    observed = ((run or {}).get("snapshots") or {}).get("native_textures") or {}
    return sum(_counts(observed.get("dispatches(ctx1/dxt1/dxt3/dxt5)", "")))


def run_overview(run):
    if not run:
        return ""
    esc = lambda v: html.escape(str(v))
    snaps = run.get("snapshots", {})
    native = snaps.get("native_textures") or {}
    dispatches = _counts(native.get("dispatches(ctx1/dxt1/dxt3/dxt5)", ""))
    guard = snaps.get("guard") or {}
    exit_info = run.get("exit") or {}
    failures = [w for w in run.get("warnings", []) if w["kind"] == "gpu_failure"]
    isolation = run.get("isolation_events", [])
    fetch = run.get("texture_fetch_warnings") or {}
    tess_pipe = snaps.get("tessellation_pipeline") or {}
    tess_mod = snaps.get("tessellation_modules") or {}
    tess_warning = next((w for w in run.get("warnings", []) if w["kind"] == "capability_warning"
                         and "Failed to create one or more tessellation shaders" in w["text"]), None)
    rect = snaps.get("rect_expand") or {}
    rect_shaders = _counts(rect.get("shaders(rewritten/transform_refused/non_vertex_skipped/already_expanded_skipped)", ""))
    fsi_modules = snaps.get("fsi_shader_modules") or {}
    pipes = run.get("pipeline_creation", {})
    frame = snaps.get("frame_rate") or {}
    ceiling = snaps.get("present_ceiling") or {}
    ladder = snaps.get("brightness_summary") or {}
    clean = exit_info.get("runner_exit_status") == "0" and not failures
    rows = [
        ("Run exit", f"Runner exit status {esc(exit_info.get('runner_exit_status', 'unknown'))}; {len(failures)} GPU address fault, hang, ignored-submission or device-loss lines in the log. "
                     "A clean exit and zero failure lines do not certify other scenes or future cutscenes."),
        ("Native Metal textures", f"Dispatches CTX1/DXT1/DXT3/DXT5 = {'/'.join(map(str, dispatches))}; admission declines {esc(native.get('declined', 'unknown'))}; "
                                  f"pipeline failures {esc(native.get('pipeline_failures', 'unknown'))}; metadata failures {esc(native.get('metadata_failures', 'unknown'))}. "
                                  "Dispatch counts show the route executed; they say nothing about whether the pictures improved."),
        ("FSI shaders and pipelines", f"{esc(fsi_modules.get('candidates/native_success/native_failure', 'unknown'))} shader modules (candidates/accepted/failed); "
                                      f"{pipes.get('accepted', 0):,}/{pipes.get('observed_attempts', 0):,} logged pipeline creations accepted. Acceptance is not correct rendering."),
        ("FSI draw guard", f"{_int(guard.get('fsi_draws')):,} FSI draws, {_int(guard.get('splits')):,} splits, completion observation mean/p50/p95/p99/max = "
                           f"{esc(guard.get('completion_ms_per_group(mean/p50/p95/p99/max)', 'unknown'))} ms (submit-to-fence upper bounds, not GPU timestamps); "
                           f"risk events {esc(guard.get('risk_events', 'unknown'))}, severe events {esc(guard.get('severe_events', 'unknown'))}."),
        ("Isolated tessellation/interlock pipelines", f"{len(isolation)} isolation activations. Isolation is workload containment; a single draw can still fail."),
        ("Tessellation", f"{_int(tess_pipe.get('native_success'))}/{_int(tess_pipe.get('candidates'))} tessellation pipelines created natively; control/evaluation modules "
                         f"{esc(tess_mod.get('control(candidate/native_success/native_failure)', 'unknown'))} and {esc(tess_mod.get('evaluation', 'unknown'))}. "
                         + (f"Xenia also logged (line {tess_warning['line']}) that it failed to create one or more of its tessellation shaders. Rosette's create ledger recorded no failed shader creation "
                            f"(every vkCreateShaderModule returned success with a non-null handle). {TESSELLATION_WARNING_FINDING}" if tess_warning else
                            "No Xenia tessellation-shader warning was logged, which is what a runner with the VPERM2F128 memory-operand decode fix should show.")),
        ("Rectangle-list expansion", f"{rect_shaders[0]} vertex shaders rewritten, {rect_shaders[1]} refused (Metal has no cull distance), "
                                     f"{_int(rect.get('draws_tagged')):,} draws tagged, {_int(rect.get('declined_foreign_index')):,} rectangle-shaped draws declined because their indices were not Xenia's built-in buffer."),
        ("Invalid texture fetch constants", f"{_int(fetch.get('warnings')):,} warnings across {_int(fetch.get('distinct_constants')):,} distinct constants; types {esc(fetch.get('types', {}))}. {esc(fetch.get('scope', ''))}"),
        ("Presentation", f"{esc(frame.get('picture_frame', 'unknown'))} picture frames, {esc(frame.get('picture_fps', 'unknown'))} FPS by presents; 30 FPS ceiling waited {esc(ceiling.get('waits', 'unknown'))} times. "
                         "Not simulation speed and not a matched benchmark."),
    ]
    table = "".join(f"<tr><td>{esc(k)}</td><td>{v}</td></tr>" for k, v in rows)
    samples = [s for s in run.get("brightness_samples", []) if s["stage"] in ("swap_texture", "guest_output")]
    by_frame = {}
    for s in samples:
        by_frame.setdefault(s["frame"], {})[s["stage"]] = s
    ladder_rows = []
    for frame_number in sorted(by_frame):
        swap, out = by_frame[frame_number].get("swap_texture"), by_frame[frame_number].get("guest_output")
        white = lambda s: f"{100*s['white']/s['pixels']:.1f}%" if s and s["pixels"] else "unread"
        mean = lambda s: "/".join(map(str, s["mean_rgb"])) if s else "unread"
        flag = " (mostly white)" if swap and swap["pixels"] and swap["white"]/swap["pixels"] >= 0.9 else ""
        ladder_rows.append(f"<tr><td>{frame_number}{flag}</td><td>{mean(swap)}</td><td>{white(swap)}</td><td>{mean(out)}</td><td>{white(out)}</td></tr>")
    ladder_table = ""
    if ladder_rows:
        ladder_table = f"""<details><summary>Sampled frame brightness ({len(ladder_rows)} frames)</summary>
<p>Channel means are bytes of the stored swap texture (raw storage order) and of Xenia's gamma-pass output; "white" is the fraction of pixels with every channel at 240 or above. Sparse samples; they do not identify the scene or the render pass that produced a bright region.</p>
<div class="scroll"><table><thead><tr><th>Frame</th><th>Swap texture mean RGB</th><th>Swap white</th><th>Gamma output mean RGB</th><th>Output white</th></tr></thead><tbody>{''.join(ladder_rows)}</tbody></table></div>
<p>Brightness ladder summary: {esc(ladder.get('samples', 'unknown'))} samples, {esc(ladder.get('white_transitions', 'unknown'))} white transitions, last sampled frame {esc(ladder.get('last_frame', 'unknown'))}.</p></details>"""
    badge = "Clean exit" if clean else "Needs review"
    return f"""<h3>Supplied run · rendering-relevant observations</h3>
<p>Run {esc(run.get('run_id', 'unknown'))} · build <code>{esc(str(run.get('build', 'unknown'))[:16])}…</code> · {esc(exit_info.get('started_utc', '?'))} to {esc(exit_info.get('finished_utc', '?'))}. Counters are the log's own cumulative final lines.</p>
<div class="cards"><div class="card"><b>{badge}</b>runner exit {esc(exit_info.get('runner_exit_status', 'unknown'))}, {len(failures)} GPU failure lines</div><div class="card"><b>{sum(dispatches):,}</b>native texture dispatches ({dispatches[0]:,} CTX1)</div><div class="card"><b>{len(isolation)}</b>isolated tessellation/interlock pipelines</div><div class="card"><b>{_int(fetch.get('warnings')):,}</b>invalid texture-fetch warnings</div></div>
<div class="scroll"><table><thead><tr><th>Observation</th><th>Value (as logged)</th></tr></thead><tbody>{table}</tbody></table></div>
{ladder_table}"""
