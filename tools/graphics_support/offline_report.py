"""Compiler evidence view; deliberately separate from rendering attestations."""
from collections import Counter, defaultdict
import html
import json
from pathlib import Path

from .iso_offline import STAGES, offline_summary, shader_tag_matrix, unknown_reason
from .vertex_layout import vertex_layout_view


def offline_view(snapshot):
    result = snapshot.get("iso_offline")
    if not result:
        return "", [], []
    esc = lambda v: html.escape(str(v))
    summary = offline_summary(result)
    tag_summary, tag_rows = shader_tag_matrix(result)
    total = summary["unique_programs"]
    pct = f"{summary['compiler_ready_percent']:.3f}%" if total else "Unknown"
    sweep = result.get("sweep", {})
    sweep_note = (f"<p class=\"note\">Partial compiler sweep: {sweep.get('checkpointed_programs',0):,} programs have saved outcomes; {sweep.get('uncheckpointed_programs',0):,} remain untested. The percentage is a confirmed compiler-ready lower bound, not a final compatibility result.</p>"
                  if sweep and not sweep.get("complete") else "")
    tags = {t["asset_id"]: t for t in result["tags"]}
    refs = defaultdict(list)
    for r in result["references"]:
        if r.get("module_id"):
            refs[r["module_id"]].append(r)
    rows, failures = [], Counter()
    for m in result["modules"]:
        first_fail = next((s for s in STAGES if m["checks"][s]["status"] == "fail"), None)
        ready = all(m["checks"][s]["status"] == "pass" for s in STAGES)
        state = "ready" if ready else "failed check" if first_fail else "unknown"
        first_unknown = next((s for s in STAGES if m["checks"][s]["status"] == "unknown"), "")
        stop = first_fail or (first_unknown if not ready else "")
        check = m["checks"].get(stop, {})
        reason = check.get("reason") or check.get("error", "")
        if first_fail and not reason and check.get("log"):
            try:
                with Path(check["log"]).open() as stream:
                    reason = stream.read(1000).strip()
            except OSError:
                reason = "Diagnostic log unavailable"
        if first_fail:
            failures[first_fail] += 1
        mapped = refs[m["id"]]
        names = sorted({tags[r["asset_id"]]["name"] for r in mapped})
        maps = sorted({tags[r["asset_id"]]["map"] for r in mapped})
        rows.append([m["id"], m["stage"], state, stop, len(mapped), names, maps, reason,
                     check.get("log", ""), unknown_reason(m)])
    stages = "".join(f"<tr><td>{esc(stage)}</td><td>{summary['stages'][stage].get('pass',0):,}</td><td>{summary['stages'][stage].get('fail',0):,}</td><td>{summary['stages'][stage].get('unknown',0):,}</td></tr>" for stage in STAGES)
    stage_totals = Counter(m["stage"] for m in result["modules"])
    ready_by_stage = Counter(m["stage"] for m in result["modules"] if all(m["checks"][s]["status"] == "pass" for s in STAGES))
    by_stage = "".join(f"<tr><td>{esc(stage)}</td><td>{n:,}</td><td>{ready_by_stage[stage]:,}</td><td>{100*ready_by_stage[stage]/n:.3f}%</td></tr>" for stage,n in sorted(stage_totals.items()))
    texture = result.get("texture_check", {})
    loaders = texture.get("loaders", [])
    loader_ready = sum(all(c["status"] == "pass" for c in m["checks"].values()) for m in loaders)
    loader_table = "".join(f"<tr><td>{esc(m['name'])}</td><td>{esc(' · '.join(k+': '+v['status'] for k,v in m['checks'].items()))}</td></tr>" for m in loaders)
    formats = "".join(f"<tr><td>{esc(k)}</td><td>{esc(texture.get('format_names',{}).get(k,'Unknown Halo format'))}</td><td>{v:,}</td><td>Resource pixels unverified</td></tr>" for k,v in sorted(texture.get("formats",{}).items(),key=lambda kv:int(kv[0])))
    block = f"""<section id="iso-offline"><h2>Direct ISO shader compiler results</h2>
<p>{esc(result['scope'])}</p>
{sweep_note}
<div class="cards"><div class="card"><b>{pct}</b>unique ISO shaders compiler-ready in the tested profile</div><div class="card"><b>{summary['compiler_ready']:,} / {total:,}</b>complete translation → rewrite → validation → MSL → AIR</div><div class="card"><b>{summary['compiler_fail']:,}</b>failed compiler checks</div><div class="card"><b>{summary['compiler_unknown']:,}</b>unknown / unresolved runtime inputs</div></div>
<p>Unknown reasons: {esc(' · '.join(f'{n:,} {reason}' for reason,n in summary['unknown_reasons'].items()) or 'none')}. Untested shaders have not failed a compiler. Runtime vertex layouts require verified declarations; invented strides cannot establish support.</p>
<p>{summary['extracted_references']:,} extracted references · {summary['compiler_ready_references']:,} references compiler-ready ({summary['reference_ready_percent'] or 0:.3f}%) · {summary['shader_tags']:,} shader-family tags · {summary['empty_tags']:,} empty tags · {summary['absent_slots']:,} null slots · {summary['extraction_unknown_slots']:,} unreadable slots · {summary['tag_parse_unknown']:,} unparsed tags.</p>
<p class="note">This percentage measures compiler readiness of {total:,} extracted unique programs under the displayed profile. It is not the percentage of Halo 3 that renders correctly. Empty/null slots are not failed shaders; extraction gaps remain explicit and outside this compiler denominator. Runtime vertex declarations, shader pairings, tessellation and other pipeline permutations remain unverified.</p>
<p>The offline translator runs natively on the ARM CPU. It tests Xenia translation sources and current Rosette shader rewrites; it does not test Rosette's x86 execution or certify the installed runner. No game shaders execute on the GPU.</p>
<h3>Compiler outcomes mapped to ISO shader tags</h3>
<p>{tag_summary['tags']:,} shader tags · {tag_summary['compiler_ready_slots']:,}/{tag_summary['extracted_slots']:,} extracted program slots passed all compiler stages · {tag_summary['absent_slots']:,} null slots · {tag_summary['unknown_slots']:,} unknown slots. Tag-level counts are not graphical support percentages; pipeline pairings, runtime constants, resources and correct pixels remain unverified.</p>
<div class="toolbar"><input id="shaderTagSearch" aria-label="Search ISO shader tags" placeholder="Shader tag name, map or asset ID"><select id="shaderTagState" aria-label="Shader tag compiler state"><option value="">All tag states</option><option>compiler_ready</option><option>compiler_failed</option><option>compiler_unknown</option><option>no_compiled_program</option><option>tag_parse_unknown</option></select><button id="shaderTagExport">Export matching tag outcomes</button></div>
<p><span id="shaderTagMatches"></span><button id="shaderTagPrev">Previous</button><button id="shaderTagNext">Next</button><span id="shaderTagPage"></span></p><div class="scroll"><table><thead><tr><th>Tag / map</th><th>Tag state</th><th>Slots</th><th>Absent</th><th>Extracted</th><th>Compiler-ready</th><th>Failed</th><th>Unknown</th></tr></thead><tbody id="shaderTagRows"></tbody></table></div>
<p><label>Compiler-readiness target <input id="isoTarget" type="number" min="0" max="100" step="0.1" value="98">%</label><span id="isoNeeded"></span></p>
<div class="scroll"><table><thead><tr><th>Shader stage</th><th>Unique programs</th><th>Compiler-ready</th><th>Readiness</th></tr></thead><tbody>{by_stage}</tbody></table></div>
<div class="scroll"><table><thead><tr><th>Offline check</th><th>Pass</th><th>Fail</th><th>Unknown / not reached</th></tr></thead><tbody>{stages}</tbody></table></div>
<details><summary>Tested physical-device features and interface</summary><pre>{esc(json.dumps(result['profile'],indent=2))}</pre></details>
{vertex_layout_view(result)}
<h3>Find shader results by map, tag name or hash</h3><div class="toolbar"><input id="isoSearch" aria-label="Search ISO shaders" placeholder="Shader name, map, hash or reason"><select id="isoState" aria-label="ISO compiler state"><option value="">All compiler states</option><option>ready</option><option>failed check</option><option>unknown</option></select><select id="isoStage" aria-label="ISO shader stage"><option value="">Both stages</option><option>ps</option><option>vs</option></select><select id="isoReason" aria-label="ISO unknown reason"><option value="">All unknown reasons</option><option>untested</option><option>runtime vertex layout</option><option>stale evidence</option><option>incomplete check</option></select><button id="isoExport">Export matching compiler results</button></div>
<p><span id="isoMatches"></span><button id="isoPrev">Previous</button><button id="isoNext">Next</button><span id="isoPage"></span></p><div class="scroll"><table><thead><tr><th>Hash / stage</th><th>Mapped tags and maps</th><th>References</th><th>Compiler state / stopping check</th></tr></thead><tbody id="isoRows"></tbody></table></div>
<h3>Texture evidence</h3><p>{texture.get('subimages',0):,} bitmap subimages across {len(texture.get('formats',{}))} Halo format IDs. <strong>Texture payload support is unknown:</strong> pixel resources, interleaving, packed mips and sampling have not been decoded and compared.</p>
<p>{loader_ready:,}/{len(loaders):,} Xenia texture-loader source kernels compile through SPIR-V, Rosette hardening, MSL and AIR. Kernel acceptance tests the conversion code, and does not establish that any ISO texture payload is correct.</p>
<details><summary>Texture-loader compiler checks</summary><table><thead><tr><th>Loader</th><th>Results</th></tr></thead><tbody>{loader_table}</tbody></table></details>
<details><summary>ISO bitmap formats</summary><table><thead><tr><th>Halo format ID</th><th>Name</th><th>Subimages</th><th>Payload status</th></tr></thead><tbody>{formats}</tbody></table></details>
<details><summary>Compiler/extraction provenance</summary><pre>{esc(json.dumps({k:v for k,v in result.items() if k not in ('modules','tags','references','texture_check','neutral_vertex_layout','vertex_format_matrix')},indent=2))}</pre></details>
</section>"""
    return block, rows, tag_rows


def texture_view(snapshot):
    """Browse every enumerated bitmap subimage, without implying pixel decode."""
    from .texture_checks import HALO_FORMATS
    rows = [[a["id"], a["map"], a["name"], i.get("index", n), i.get("width", "unknown"), i.get("height", "unknown"),
             i.get("depth", "unknown"), i.get("mip_count", "unknown"), i["format"], HALO_FORMATS.get(i["format"], "Unknown"),
             i.get("type", "unknown"), i.get("curve", "unknown"), i.get("payload_status", "unverified")]
            for a in snapshot["iso"]["assets"] for n,i in enumerate(a.get("subimages", []))]
    block = f"""<section><h2>Browse ISO texture metadata</h2>
<p>{len(rows):,} bitmap subimages, including repeated tags in different maps. All enumerated texture tags also appear in the asset inventory below. Pixel previews and payload decoding remain unavailable.</p>
<div class="toolbar"><input id="textureSearch" aria-label="Search textures" placeholder="Texture name, map or format name"><input id="textureFormat" aria-label="Texture Halo format ID" type="number" placeholder="Halo format ID"><button id="textureExport">Export matching texture metadata</button></div>
<p><span id="textureMatches"></span><button id="texturePrev">Previous</button><button id="textureNext">Next</button><span id="texturePage"></span></p>
<div class="scroll"><table><thead><tr><th>Map / texture / subimage</th><th>Dimensions / mip count</th><th>Halo format / type / curve</th><th>Pixel support</th></tr></thead><tbody id="textureRows"></tbody></table></div></section>"""
    return block, rows


OFFLINE_SCRIPT = r"""
if(data.isoModules?.length){
 let p=0, selected=data.isoModules;const rowset=data.isoModules;
 function isoTarget(){const rate=Number(by('isoTarget').value),ready=rowset.filter(r=>r[2]==='ready').length;by('isoNeeded').textContent=Number.isFinite(rate)&&rate>=0&&rate<=100?' '+Math.max(0,Math.ceil(rate*rowset.length/100)-ready).toLocaleString()+' additional unique programs must pass every compiler stage.':' Enter a target from 0 to 100.'}by('isoTarget').oninput=isoTarget;isoTarget();
 function filterIso(){const q=by('isoSearch').value.toLowerCase(),s=by('isoState').value,g=by('isoStage').value,u=by('isoReason').value;selected=rowset.filter(r=>(!s||r[2]===s)&&(!g||r[1]===g)&&(!u||r[9]===u)&&(!q||[r[0],r[3],r[5].join(' '),r[6].join(' '),r[7],r[9]].join(' ').toLowerCase().includes(q)));p=0;drawIso()}
 function drawIso(){const body=by('isoRows');body.replaceChildren();for(const r of selected.slice(p*25,p*25+25)){const tr=document.createElement('tr');for(const v of [r[0].slice(0,19)+'… / '+r[1],r[5].slice(0,3).join('\n')+'\n'+r[6].join(', '),r[4].toLocaleString(),r[2]+(r[3]?' / '+r[3]:'')+(r[7]?'\n'+r[7]:'')]){const td=document.createElement('td');td.textContent=v;td.style.whiteSpace='pre-line';tr.append(td)}const details=document.createElement('details'),summary=document.createElement('summary'),pre=document.createElement('pre');summary.textContent='All mapped tag names ('+r[5].length+')';pre.textContent=r[5].join('\n');details.append(summary,pre);tr.children[1].append(details);tr.title=r[0]+'\nEvidence log: '+r[8];body.append(tr)}by('isoMatches').textContent=selected.length.toLocaleString()+' matching unique shaders · ';by('isoPage').textContent=selected.length?'Page '+(p+1)+' of '+Math.ceil(selected.length/25):'No matches';by('isoPrev').disabled=p===0;by('isoNext').disabled=(p+1)*25>=selected.length}
 let timer;by('isoSearch').oninput=()=>{clearTimeout(timer);timer=setTimeout(filterIso,150)};by('isoState').oninput=filterIso;by('isoStage').oninput=filterIso;by('isoReason').oninput=filterIso;by('isoPrev').onclick=()=>{p--;drawIso()};by('isoNext').onclick=()=>{p++;drawIso()};by('isoExport').onclick=()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(selected.map(r=>({module_id:r[0],stage:r[1],state:r[2],stopping_check:r[3],references:r[4],tag_names:r[5],maps:r[6],reason:r[7],log:r[8],unknown_reason:r[9]})),null,2)],{type:'application/json'})),a=document.createElement('a');a.href=url;a.download='iso-shader-results.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};drawIso()
}
if(data.shaderTagRows?.length){
 let page=0,selected=data.shaderTagRows;
 function filterShaderTags(){const q=by('shaderTagSearch').value.toLowerCase(),s=by('shaderTagState').value;selected=data.shaderTagRows.filter(r=>(!s||r[4]===s)&&(!q||[r[0],r[1],r[2],r[3]].join(' ').toLowerCase().includes(q)));page=0;drawShaderTags()}
 function drawShaderTags(){const body=by('shaderTagRows');body.replaceChildren();for(const r of selected.slice(page*25,page*25+25)){const tr=document.createElement('tr');for(const v of [r[1]+'\n'+r[2]+'\n'+r[0],r[4],r[5],r[6],r[7],r[8],r[9],r[10]]){const td=document.createElement('td');td.textContent=v;td.style.whiteSpace='pre-line';tr.append(td)}body.append(tr)}by('shaderTagMatches').textContent=selected.length.toLocaleString()+' matching shader tags · ';by('shaderTagPage').textContent=selected.length?'Page '+(page+1)+' of '+Math.ceil(selected.length/25):'No matches';by('shaderTagPrev').disabled=page===0;by('shaderTagNext').disabled=(page+1)*25>=selected.length}
 let timer;by('shaderTagSearch').oninput=()=>{clearTimeout(timer);timer=setTimeout(filterShaderTags,150)};by('shaderTagState').oninput=filterShaderTags;by('shaderTagPrev').onclick=()=>{page--;drawShaderTags()};by('shaderTagNext').onclick=()=>{page++;drawShaderTags()};by('shaderTagExport').onclick=()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(selected.map(r=>({asset_id:r[0],name:r[1],map:r[2],class:r[3],state:r[4],slots:r[5],absent:r[6],extracted:r[7],compiler_ready:r[8],failed:r[9],unknown:r[10]})),null,2)],{type:'application/json'})),a=document.createElement('a');a.href=url;a.download='iso-shader-tag-outcomes.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};drawShaderTags()
}
if(data.textureRows?.length){
 let page=0,selected=data.textureRows;
 function filterTextures(){const q=by('textureSearch').value.toLowerCase(),f=by('textureFormat').value;selected=data.textureRows.filter(r=>(f===''||r[8]===Number(f))&&(!q||[r[0],r[1],r[2],r[9]].join(' ').toLowerCase().includes(q)));page=0;drawTextures()}
 function drawTextures(){const body=by('textureRows');body.replaceChildren();for(const r of selected.slice(page*25,page*25+25)){const tr=document.createElement('tr');for(const v of [r[1]+'\n'+r[2]+' / subimage '+r[3],r[4]+' × '+r[5]+' × '+r[6]+' / '+r[7]+' mips',r[8]+' '+r[9]+' / type '+r[10]+' / curve '+r[11],r[12]]){const td=document.createElement('td');td.textContent=v;td.style.whiteSpace='pre-line';tr.append(td)}tr.title=r[0];body.append(tr)}by('textureMatches').textContent=selected.length.toLocaleString()+' matching subimages · ';by('texturePage').textContent=selected.length?'Page '+(page+1)+' of '+Math.ceil(selected.length/25):'No matches';by('texturePrev').disabled=page===0;by('textureNext').disabled=(page+1)*25>=selected.length}
 let timer;by('textureSearch').oninput=()=>{clearTimeout(timer);timer=setTimeout(filterTextures,150)};by('textureFormat').oninput=filterTextures;by('texturePrev').onclick=()=>{page--;drawTextures()};by('textureNext').onclick=()=>{page++;drawTextures()};by('textureExport').onclick=()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(selected.map(r=>({asset_id:r[0],map:r[1],name:r[2],subimage:r[3],width:r[4],height:r[5],depth:r[6],mips:r[7],format:r[8],format_name:r[9],type:r[10],curve:r[11],payload_status:r[12]})),null,2)],{type:'application/json'})),a=document.createElement('a');a.href=url;a.download='iso-texture-metadata.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};drawTextures()
}
"""
