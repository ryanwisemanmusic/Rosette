"""Self-contained report with searchable asset inventory and conservative metrics."""
from collections import Counter
import html
import json
import shutil
from pathlib import Path

from .coverage import states, summarize
from .offline_report import OFFLINE_SCRIPT, offline_view, texture_view
from .native_metal import native_view, verify_native
from .live_metal import live_view, verify_live
from .tag_checks import tag_view
from .run_view import run_overview, performance_overview, performance_measurements
from .progress import progress_view
from .offline_checks import checks_view, verify_checks
from .hdr_chain import chain_view, verify_chain
from .fsi_sampling import sampling_view, verify_sampling
from .white_orbs import white_orb_view, verify_hdr
from .hdr_resolve import resolve_view, verify_resolve, verify_record
from .gfxr_capture import capture_view, verify_capture_record


def json_script(value):
    return json.dumps(value, ensure_ascii=True, separators=(",", ":")).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")


def render(snapshot):
    verified = states(snapshot)
    summary = summarize(snapshot, verified)
    all_counts = summary["coverage"].get("all", {"total": 0, "confirmed": 0, "unknown": 0, "confirmed_coverage_percent": None})
    rows = [[a["id"], a["map"], a["name"], a["class"], a["category"], verified[a["id"]]["correct_render"],
             a["metadata_status"], sorted({i["format"] for i in a.get("subimages", [])})] for a in snapshot["iso"]["assets"]]
    run, archive = snapshot.get("run") or {}, snapshot.get("shader_archive") or {}
    esc = lambda value: html.escape(str(value))
    offline_html, offline_rows, shader_tag_rows = offline_view(snapshot)
    texture_html, texture_rows = texture_view(snapshot)
    native_html = native_view(snapshot)
    live_html = live_view(snapshot)
    tag_html = tag_view(snapshot)
    progress_html = progress_view(snapshot)
    sampling_html = sampling_view(snapshot)
    orb_html = white_orb_view(snapshot)
    resolve_html = resolve_view(snapshot)
    checks_html = checks_view(snapshot)
    chain_html = chain_view(snapshot)
    capture_html = capture_view(snapshot)
    category_rows = "".join(f"<tr><td>{esc(k)}</td><td>{v['total']:,}</td><td>{v['confirmed']:,}</td><td>{v['known_failure']:,}</td><td>{v['conflict']:,}</td><td>{v['unknown']:,}</td><td>{v['confirmed_coverage_percent']:.3f}%</td></tr>" for k, v in summary["coverage"].items())
    maps = "".join(f"<tr><td>{esc(m['path'])}</td><td>{esc(m['status'])}</td><td>{m.get('graphics_tags', 0):,}</td><td>{esc(m.get('error', m.get('note', '')))}</td></tr>" for m in snapshot["iso"]["maps"])
    formats = "".join(f"<tr><td>{esc(k)}</td><td>{v:,}</td><td>Payload decoding and fidelity unverified</td></tr>" for k, v in summary["bitmap_subimages_by_halo_format_id"].items())
    backlog = "".join(f"<tr><td>{esc(b['category'])}</td><td>{esc(b['class'])}</td><td>{esc(b['state'])}</td><td>{b['instances']:,}</td></tr>" for b in summary["backlog"])
    attempts = run.get("pipeline_creation", {})
    stage_rows = []
    selected = [m for m in archive.get("modules", []) if m["current_run_guest_match"]]
    for stage in ("rewrite", "spirv_validation", "msl_conversion", "air_compilation"):
        counts = Counter(m.get("checks", {}).get(stage, {}).get("status", "unknown") for m in selected)
        stage_rows.append(f"<tr><td>{stage}</td><td>{counts['pass']:,}</td><td>{counts['fail']:,}</td><td>{counts['unknown']:,}</td></tr>")
    host = "".join(f"<tr><td>{esc(k)}</td><td>{v.get('calls', 0):,}</td><td>{v.get('total_us', 0)/1000:,.3f} ms</td><td>{v.get('max_us', 0)/1000:,.3f} ms</td></tr>" for k, v in run.get("host_cost", {}).items())
    events = "".join(f"<tr><td>{esc(e['kind'])}</td><td>{e['line']}</td><td>{esc(json.dumps(e['fields']))}</td></tr>" for e in run.get("events", []))
    warnings = "".join(f"<li>Line {w['line']} · {esc(w['kind'])}: {esc(w['text'])}</li>" for w in run.get("warnings", []))
    snapshots = esc(json.dumps(run.get("snapshots", {}), indent=2))
    failure_candidates = esc(json.dumps(run.get("failure_candidates", []), indent=2))
    total, confirmed = all_counts["total"], all_counts["confirmed"]
    rate = f"{100*confirmed/total:.3f}%" if total else "Unknown"
    headline = "No assets evaluated yet" if sum(v["correct_render"] != "unknown" for v in verified.values()) == 0 else "Build-scoped evidence recorded"
    if snapshot.get("iso_offline"):
        headline = "Offline ISO compiler results available · rendering unverified" if not confirmed else "ISO compiler and rendering evidence available"
    return f"""<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rosette graphics evidence tracker</title><style>
:root{{color-scheme:dark;--bg:#10151d;--panel:#1a2230;--text:#e6edf5;--muted:#a9b9ca;--accent:#7dd6c5}}*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui}}main{{max-width:1400px;margin:auto;padding:36px 24px}}h1{{font-size:30px;margin:0}}h2{{font-size:21px;margin:0 0 12px}}h3{{font-size:16px}}p{{color:var(--muted)}}section{{margin:24px 0;background:var(--panel);padding:22px;border-radius:12px}}.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:14px;margin:24px 0}}.card{{padding:20px;background:var(--panel);border-radius:12px}}.card b{{display:block;font-size:30px;color:var(--accent)}}.note{{border-left:3px solid var(--accent);padding-left:14px}}.scroll{{overflow:auto}}table{{border-collapse:collapse;width:100%;font-size:13px}}th,td{{text-align:left;border-bottom:1px solid #344253;padding:10px;vertical-align:top}}th{{color:var(--accent)}}td{{overflow-wrap:anywhere}}code,pre{{font-size:12px}}pre{{white-space:pre-wrap;overflow-wrap:anywhere}}button,input,select{{font:inherit;background:#101923;color:var(--text);border:1px solid #54697e;border-radius:6px;padding:8px;margin:4px}}button{{cursor:pointer}}label{{display:inline-flex;gap:6px;align-items:center}}summary{{cursor:pointer;font-weight:600}}small{{color:var(--muted)}}svg{{width:100%;height:170px}}#inventory td:nth-child(2){{min-width:260px}}.toolbar{{display:flex;flex-wrap:wrap;align-items:center}}#search{{flex:1;min-width:230px}}a{{color:var(--accent)}}
</style><main><h1>Rosette graphics evidence tracker</h1><p>{esc(headline)} · {esc(snapshot['context']['scenario'])} · build {esc(snapshot['context']['build'] or 'unknown')}</p>
<p class="note">{esc(summary['claim'])} Compiler acceptance cannot establish correct colours, lighting, geometry or bloom.</p>
{progress_html}
{chain_html}
{capture_html}
{resolve_html}
{orb_html}
{checks_html}
{offline_html}
{sampling_html}
{live_html}
{tag_html}
{native_html}
{texture_html}
<div class="cards"><div class="card"><b>{total:,}</b>enumerated graphics tag instances</div><div class="card"><b>{confirmed:,}</b>confirmed rendering · {rate} coverage</div><div class="card"><b>{all_counts['unknown']:,}</b>rendering unverified · not unsupported</div><div class="card"><b>{attempts.get('accepted', 0):,}/{attempts.get('observed_attempts', 0):,}</b>logged pipeline creations accepted</div></div>
<section><h2>Fixed denominator and next target</h2><p>{esc(snapshot['iso']['scope'])}. Repeated tags in different maps count separately; this is not a count of independent texture payloads. Shared resource containers and unclassified classes are outside this denominator.</p>
<p>ISO SHA-256 <code>{esc(snapshot['iso']['sha256'])}</code><br>Inventory policy <code>{esc(snapshot['iso']['policy'])}</code></p>
<div class="scroll"><table><thead><tr><th>Category</th><th>Total</th><th>Confirmed</th><th>Known failure</th><th>Conflict</th><th>Unknown</th><th>Confirmed coverage</th></tr></thead><tbody>{category_rows}</tbody></table></div>
<p><label>Target coverage <input id="target" type="number" min="0" max="100" step="0.1" value="2">%</label><span id="needed"></span></p><small>Proof must identify each counted asset and this build, driver and scenario. ISO changes or a different inventory policy require a new baseline.</small></section>
<section><h2>Asset inventory</h2><p>Search names and map paths, filter a class or Halo bitmap format ID, then export the matching IDs for a proof manifest. Exporting IDs does not mark them supported.</p>
<div class="toolbar"><input id="search" placeholder="Search name, class, map or asset ID" aria-label="Search assets"><select id="category" aria-label="Category"><option value="">All categories</option></select><select id="state" aria-label="Evidence state"><option value="">All rendering states</option><option>unknown</option><option>confirmed</option><option>known_failure</option><option>conflict</option></select><input id="format" placeholder="Bitmap format ID" type="number" aria-label="Halo bitmap format ID"><button id="export">Export matching IDs</button></div>
<p><span id="matches"></span><button id="prev">Previous</button><button id="next">Next</button><span id="page"></span></p>
<div class="scroll"><table id="inventory"><thead><tr><th>Map / tag</th><th>Name</th><th>Class / category</th><th>Rendering evidence</th><th>Metadata / formats</th></tr></thead><tbody id="assets"></tbody></table></div></section>
<section><h2>Observed shader readiness</h2><p>{esc(archive.get('scope', 'No archive supplied'))}</p><p>{archive.get('files_seen', 0):,} archived files · {len(archive.get('modules', [])):,} unique content/role records · {archive.get('matched_fsi_guest_hashes', 0):,}/{archive.get('logged_fsi_guest_hashes', 0):,} exact logged FSI guest hashes found · {len(archive.get('unreadable', [])):,} unreadable records.</p>
<div class="scroll"><table><thead><tr><th>Check on matched guest modules</th><th>Pass</th><th>Fail</th><th>Unknown / not run</th></tr></thead><tbody>{''.join(stage_rows)}</tbody></table></div>
<p class="note">These GPU modules have no verified mapping to ISO shader tags. Compilation percentages never increase the ISO rendering coverage counter. No game shaders are dispatched by this tool.</p>
<details><summary>Offline tool identities and rewrite provenance</summary><pre>{esc(json.dumps(archive.get('offline_check', {}), indent=2))}</pre></details></section>
<section><h2>Timing and health evidence</h2>{run_overview(run)}{performance_overview(run)}{performance_measurements(snapshot.get('performance_measurements'))}<p>Run {esc(run.get('run_id', 'none'))} · {esc(json.dumps(run.get('driver')))}. {esc(run.get('cadence_scope', 'No runtime log'))}. Horizontal position is the present counter, not elapsed time.</p><svg id="cadence" role="img" aria-label="Observed presentation cadence by present counter" viewBox="0 0 1000 170"></svg>
<p>Host costs are cumulative final snapshots. Queue-submit time includes bridge backpressure. These timers overlap; adding them would double-count time. Fence observation is an upper bound including CPU and queue delay, not a GPU timestamp.</p>
<div class="scroll"><table><thead><tr><th>Host stage</th><th>Calls</th><th>Total</th><th>Maximum call</th></tr></thead><tbody>{host}</tbody></table></div>
<details><summary>Guard, robustness and CPU route counters</summary><pre>{snapshots}</pre></details>
<details><summary>Failed timing-group boundary pipeline candidates</summary><p>First and last draws are candidates, not proof of fault origin; intermediate draws and resource values remain unknown.</p><pre>{failure_candidates}</pre></details>
<details><summary>Watchdog events ({len(run.get('events', []))})</summary><div class="scroll"><table><thead><tr><th>Event</th><th>Log line</th><th>Fields</th></tr></thead><tbody>{events}</tbody></table></div></details>
<details><summary>Failure / advisory observations ({len(run.get('warnings', []))})</summary><ul>{warnings}</ul></details><p>Zero reported faults in a supplied log does not certify future cutscenes or system health. Advisory memexport warnings need actual export/resource evidence.</p></section>
<section><h2>Verification backlog</h2><p>Largest unverified class groups help choose tests. Instance count measures inventory breadth, not screen importance or predicted FPS gains.</p><div class="scroll"><table><thead><tr><th>Category</th><th>Class</th><th>State</th><th>Instances</th></tr></thead><tbody>{backlog}</tbody></table></div>
<details><summary>Bitmap subimage format distribution (Halo namespace)</summary><p>Format IDs are Halo cache enums, not Vulkan/Xenos format IDs. Dimensions/mips live in snapshot.json; resources are not decoded.</p><table><thead><tr><th>Format ID</th><th>Subimages</th><th>Fidelity</th></tr></thead><tbody>{formats}</tbody></table></details>
<details><summary>Map inventory and parse gaps</summary><table><thead><tr><th>Map</th><th>Status</th><th>Graphics tags</th><th>Gap</th></tr></thead><tbody>{maps}</tbody></table></details></section>
<small>Read-only ISO/log/archive analysis. Full runtime gates remain separate. Evidence file hashes are verified when this report is generated; the HTML is a saved snapshot.</small></main>
<script id="data" type="application/json">{json_script({'rows': rows, 'total': total, 'confirmed': confirmed, 'cadence': run.get('cadence', []), 'isoModules': offline_rows, 'shaderTagRows': shader_tag_rows, 'textureRows': texture_rows})}</script>
<script>
const data=JSON.parse(document.getElementById('data').textContent), by=id=>document.getElementById(id);let page=0, matches=data.rows;
{OFFLINE_SCRIPT}
for(const value of [...new Set(data.rows.map(r=>r[4]))].sort()){{const o=document.createElement('option');o.value=value;o.textContent=value;by('category').append(o)}}
function filter(){{const q=by('search').value.toLowerCase(),c=by('category').value,s=by('state').value,f=by('format').value;matches=data.rows.filter(r=>(!q||r.slice(0,5).join(' ').toLowerCase().includes(q))&&(!c||r[4]===c)&&(!s||r[5]===s)&&(f===''||r[7].includes(Number(f))));page=0;draw()}}
function draw(){{const body=by('assets');body.replaceChildren();for(const r of matches.slice(page*50,page*50+50)){{const tr=document.createElement('tr');for(const v of [r[1]+' / 0x'+r[0].split(':').slice(-2,-1)[0],r[2],r[3]+' / '+r[4],r[5],r[6]+(r[7].length?' / '+r[7].join(', '):'')]){{const td=document.createElement('td');td.textContent=v;tr.append(td)}}tr.title=r[0];body.append(tr)}}by('matches').textContent=matches.length.toLocaleString()+' matching assets · ';by('page').textContent=matches.length?'Page '+(page+1)+' of '+Math.ceil(matches.length/50):'No matches';by('prev').disabled=page===0;by('next').disabled=(page+1)*50>=matches.length}}
let timer;by('search').oninput=()=>{{clearTimeout(timer);timer=setTimeout(filter,180)}};for(const id of ['category','state','format'])by(id).oninput=filter;
by('prev').onclick=()=>{{page--;draw()}};by('next').onclick=()=>{{page++;draw()}};
by('export').onclick=()=>{{const blob=new Blob([JSON.stringify({{asset_ids:matches.map(r=>r[0])}},null,2)],{{type:'application/json'}}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='asset-ids.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)}};
function target(){{const p=Number(by('target').value);by('needed').textContent=Number.isFinite(p)&&p>=0&&p<=100?' '+Math.max(0,Math.ceil(p*data.total/100)-data.confirmed).toLocaleString()+' additional confirmed instances needed.':' Enter a target from 0 to 100.'}}by('target').oninput=target;target();draw();
const svg=by('cadence'),ns='http://www.w3.org/2000/svg';function node(tag,attrs,text){{const n=document.createElementNS(ns,tag);for(const [k,v]of Object.entries(attrs))n.setAttribute(k,v);if(text)n.textContent=text;svg.append(n);return n}}
if(data.cadence.length){{const maxX=Math.max(...data.cadence.map(p=>p.present)),maxY=Math.max(30,...data.cadence.map(p=>p.fps));for(const y of [0,15,30]){{const sy=145-y/maxY*125;node('line',{{x1:45,x2:980,y1:sy,y2:sy,stroke:'#344253'}});node('text',{{x:2,y:sy+4,fill:'#a9b9ca','font-size':12}},y+' FPS')}}node('polyline',{{points:data.cadence.map(p=>(45+p.present/maxX*935)+','+(145-p.fps/maxY*125)).join(' '),fill:'none',stroke:'#7dd6c5','stroke-width':2}});node('text',{{x:45,y:165,fill:'#a9b9ca','font-size':12}},'Present 0');node('text',{{x:860,y:165,fill:'#a9b9ca','font-size':12}},'Present '+maxX)}}else node('text',{{x:40,y:80,fill:'#a9b9ca'}},'No presentation cadence observations');
</script></html>"""


def write_snapshot(snapshot, output: Path):
    if output.exists():
        raise ValueError("Output directory already exists; preserve the baseline and choose a new directory")
    if snapshot.get("iso_offline"):
        from .iso_offline import verify_offline_artifacts
        verify_offline_artifacts(snapshot["iso_offline"])
    verify_native(snapshot)
    verify_live(snapshot)
    verify_sampling(snapshot)
    verify_hdr(snapshot)
    verify_resolve(snapshot)
    if snapshot.get('orb_regions'):
        verify_record(snapshot['orb_regions'])
    verify_checks(snapshot)
    verify_chain(snapshot)
    if snapshot.get("gfxr_capture_audit"):
        verify_capture_record(snapshot["gfxr_capture_audit"])
    verified = states(snapshot)
    rendered = render(snapshot)
    output.mkdir(parents=True)
    regions = snapshot.get('orb_regions')
    if regions and regions['verification']['status'] == 'verified':
        (output / 'assets').mkdir(exist_ok=True)
        for i, image in enumerate(regions['result']['images']):
            copied = output / 'assets' / f'orb-region-{i}.png'
            shutil.copyfile(image['path'], copied)
            from .iso import hash_file
            if hash_file(copied) != image['sha256']:
                raise ValueError('Screenshot changed during report generation')
    video = snapshot.get('white_orb_video')
    if video and video['verification']['status'] == 'verified_extraction':
        (output / 'assets').mkdir(exist_ok=True)
        for i,frame in enumerate(video['result']['frames']):
            copied = output / 'assets' / f'white-orb-{i}.png'
            shutil.copyfile(frame['path'], copied)
            from .iso import hash_file
            if hash_file(copied) != frame['sha256']:
                raise ValueError('Video frame changed during report generation')
    (output / "snapshot.json").write_text(json.dumps(snapshot, ensure_ascii=True, separators=(",", ":")))
    (output / "summary.json").write_text(json.dumps(summarize(snapshot, verified), indent=2))
    (output / "report.html").write_text(rendered)
