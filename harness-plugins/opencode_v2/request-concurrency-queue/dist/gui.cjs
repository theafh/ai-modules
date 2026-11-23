"use strict";Object.defineProperties(exports,{__esModule:{value:!0},[Symbol.toStringTag]:{value:"Module"}});const e=require("solid-js/web"),u=require("solid-js"),_=require("@opencode/plugin/gui"),te=`
.request-concurrency-status {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 8px 4px 12px;
  font-size: 12px;
  line-height: 1.45;
}

.request-concurrency-status-unavailable {
  padding: 8px 4px;
  font-style: italic;
  opacity: 0.65;
}

.request-concurrency-status-header,
.request-concurrency-status-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 4.5em 4em 5.5em 3.5em 3.5em;
  column-gap: 10px;
  align-items: baseline;
}

.request-concurrency-status-header {
  padding: 0 8px 4px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.55;
}

.request-concurrency-status-header > :not(:first-child) {
  text-align: right;
}

.request-concurrency-status-row {
  padding: 4px 8px;
  border-left: 2px solid transparent;
  border-radius: 4px;
  background: rgba(127, 127, 127, 0.06);
}

.request-concurrency-status-provider {
  min-width: 0;
  overflow: hidden;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.request-concurrency-status-active,
.request-concurrency-status-queued,
.request-concurrency-status-tokens,
.request-concurrency-status-utilization,
.request-concurrency-status-demand {
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  text-align: right;
  white-space: nowrap;
}

.request-concurrency-status-max {
  font-weight: 400;
  opacity: 0.5;
}

.request-concurrency-subagents {
  display: flex;
  gap: 8px;
  align-items: baseline;
  margin-top: 6px;
  padding: 4px 8px;
  border-left: 2px solid transparent;
  border-radius: 4px;
  background: rgba(127, 127, 127, 0.06);
}

.request-concurrency-subagents-label {
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.55;
}

.request-concurrency-subagents-count {
  font-variant-numeric: tabular-nums;
  font-weight: 600;
}

.request-concurrency-feed {
  display: flex;
  flex-direction: column;
  gap: 1px;
  max-height: 12em;
  margin-top: 10px;
  padding-top: 8px;
  border-top: 1px solid rgba(127, 127, 127, 0.25);
  overflow-y: auto;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 11px;
}

.request-concurrency-feed-title {
  padding: 0 4px 4px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.55;
}

.request-concurrency-feed-row {
  display: grid;
  grid-template-columns: auto 5em minmax(0, 0.6fr) minmax(0, 1.6fr) auto;
  column-gap: 8px;
  align-items: baseline;
  padding: 2px 4px;
  border-radius: 3px;
}

.request-concurrency-feed-time {
  font-variant-numeric: tabular-nums;
  opacity: 0.6;
}

.request-concurrency-feed-kind {
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-align: right;
  text-transform: uppercase;
}

.request-concurrency-feed-kind.is-acquired {
  color: #4ade80;
}

.request-concurrency-feed-kind.is-queued {
  color: #fbbf24;
}

.request-concurrency-feed-kind.is-released {
  opacity: 0.55;
}

.request-concurrency-feed-kind.is-dequeued {
  color: #60a5fa;
}

.request-concurrency-feed-provider,
.request-concurrency-feed-session {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.request-concurrency-feed-session {
  display: flex;
  opacity: 0.75;
}

.request-concurrency-feed-session-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.request-concurrency-feed-session-meta {
  flex: none;
  white-space: nowrap;
  opacity: 0.7;
}

.request-concurrency-feed-counts {
  text-align: right;
  white-space: nowrap;
  opacity: 0.75;
}

.request-concurrency-bar {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  min-width: 0;
  height: 28px;
  padding: 0 10px;
  border: 0;
  border-top: 1px solid rgba(127, 127, 127, 0.25);
  background: rgba(127, 127, 127, 0.06);
  color: inherit;
  font: inherit;
  font-size: 11px;
  text-align: left;
  cursor: pointer;
}

.request-concurrency-bar:hover {
  background: rgba(127, 127, 127, 0.12);
}

.request-concurrency-bar:focus-visible {
  outline: 2px solid currentColor;
  outline-offset: -2px;
}

.request-concurrency-bar::after {
  content: "›";
  margin-left: auto;
  font-size: 14px;
  line-height: 1;
  opacity: 0.4;
}

.request-concurrency-bar-label {
  flex: none;
  font-weight: 600;
  letter-spacing: 0.02em;
}

.request-concurrency-bar-items {
  display: flex;
  align-items: baseline;
  gap: 14px;
  min-width: 0;
  overflow: hidden;
}

.request-concurrency-bar-item {
  display: inline-flex;
  align-items: baseline;
  gap: 5px;
  white-space: nowrap;
}

.request-concurrency-bar-provider {
  opacity: 0.7;
}

.request-concurrency-bar-slots,
.request-concurrency-bar-queue {
  font-variant-numeric: tabular-nums;
  font-weight: 600;
}

.request-concurrency-bar-queue {
  padding: 0 3px;
  border-radius: 3px;
  background: rgba(127, 127, 127, 0.14);
  font-size: 10px;
}

.request-concurrency-bar-muted {
  font-style: italic;
  opacity: 0.6;
}

.request-concurrency-dialog .request-concurrency-status {
  padding: 0;
}
`,ne=`
.request-concurrency-config {
  display: flex;
  flex-direction: column;
  gap: 6px;
  max-height: 62vh;
  overflow-y: auto;
  padding-right: 4px;
}

.request-concurrency-config-title {
  margin-top: 6px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.55;
}

.request-concurrency-config-subtitle {
  font-size: 11px;
  font-weight: 600;
  opacity: 0.8;
}

.request-concurrency-config-group {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 6px 8px;
  border-radius: 4px;
  background: rgba(127, 127, 127, 0.06);
}

.request-concurrency-field {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 8em;
  align-items: start;
  gap: 10px;
  padding: 3px 0;
}

.request-concurrency-field-text {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 0;
}

.request-concurrency-field-help {
  font-size: 11px;
  line-height: 1.35;
  opacity: 0.55;
}

.request-concurrency-config-intro,
.request-concurrency-config-help {
  margin: 0 0 4px;
  font-size: 11px;
  line-height: 1.45;
  opacity: 0.6;
}

.request-concurrency-tabs {
  display: flex;
  gap: 4px;
  margin-bottom: 10px;
  border-bottom: 1px solid rgba(127, 127, 127, 0.25);
}

.request-concurrency-tab {
  padding: 6px 12px;
  border: none;
  border-bottom: 2px solid transparent;
  background: none;
  color: inherit;
  font: inherit;
  font-size: 12px;
  font-weight: 600;
  opacity: 0.55;
  cursor: pointer;
}

.request-concurrency-tab.is-active {
  opacity: 1;
  border-bottom-color: currentColor;
}

.request-concurrency-field-inline {
  grid-template-columns: minmax(0, 1fr) auto;
}

.request-concurrency-field-label {
  font-size: 12px;
  opacity: 0.85;
}

.request-concurrency-input {
  width: 100%;
  padding: 3px 6px;
  border: 1px solid rgba(127, 127, 127, 0.35);
  border-radius: 4px;
  background: rgba(127, 127, 127, 0.08);
  color: inherit;
  font: inherit;
  font-variant-numeric: tabular-nums;
  text-align: right;
}

.request-concurrency-config-actions {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-top: 10px;
}

.request-concurrency-save {
  padding: 5px 14px;
  border: 1px solid rgba(127, 127, 127, 0.4);
  border-radius: 4px;
  background: rgba(127, 127, 127, 0.12);
  color: inherit;
  font: inherit;
  font-weight: 600;
  cursor: pointer;
}

.request-concurrency-save:disabled {
  opacity: 0.5;
  cursor: default;
}

.request-concurrency-config-notice {
  font-size: 12px;
  opacity: 0.8;
}

.request-concurrency-config-error {
  font-size: 12px;
  color: hsl(0 70% 60%);
}
`,re={type:"object",properties:{slots:{type:"integer",minimum:0},context:{type:"integer",minimum:0},budget:{type:"integer",minimum:0},breaker:{type:"integer",minimum:0},draining:{type:"integer",minimum:0}},required:["slots","context","budget","breaker","draining"],additionalProperties:!1},ae={type:"object",properties:{providerID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},ceiling:{type:"integer",minimum:0},sessions:{type:"integer",minimum:0},activeSessionIDs:{type:"array",items:{type:"string"}},utilization:{type:"number",minimum:0,maximum:1},demand:{type:"number",minimum:0},tokensAvailable:{type:"integer",minimum:0},tokensCapacity:{type:"integer",minimum:0},tokensPausedUntil:{type:"integer",minimum:0},blocked:re,contextInFlight:{type:"integer",minimum:0},contextCapacity:{type:"integer",minimum:0},breaker:{type:"string",enum:["closed","open","half-open"]},breakerRetryAfterMs:{type:"integer",minimum:0},stalls:{type:"integer",minimum:0}},required:["providerID","active","queued","max","ceiling","utilization","demand","tokensAvailable","tokensCapacity","tokensPausedUntil","blocked","breaker","breakerRetryAfterMs","stalls"],additionalProperties:!1},se={type:"object",properties:{timestamp:{type:"integer",minimum:0},providerID:{type:"string"},kind:{type:"string",enum:["acquired","queued","released","dequeued"]},sessionID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0}},required:["timestamp","providerID","kind","sessionID","active","queued"],additionalProperties:!1},ie={type:"object",properties:{sessionID:{type:"string"},title:{type:"string"},agent:{type:"string"},directory:{type:"string"},parentID:{type:"string"}},required:["sessionID"],additionalProperties:!1},oe={type:"object",properties:{live:{type:"integer",minimum:0},calling:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},capacity:{type:"integer",minimum:0}},required:["live","calling","queued","max","capacity"],additionalProperties:!1},ce={type:"object",properties:{capacity:{type:"integer",minimum:1},refillPerMinute:{type:"integer",minimum:1},safetyFactor:{type:"number",minimum:.1,maximum:10}},required:["capacity","refillPerMinute","safetyFactor"],additionalProperties:!1},le={type:"object",properties:{contextCapacity:{type:"integer",minimum:0},contextCeiling:{type:"integer",minimum:0},reserveShare:{type:"number",minimum:0,maximum:1},smallShare:{type:"number",minimum:0,maximum:1},agingMs:{type:"integer",minimum:0},queueDeadlineMs:{type:"integer",minimum:0},breaker:{type:"object",properties:{threshold:{type:"integer",minimum:1},cooldownMs:{type:"integer",minimum:0},mode:{type:"string",enum:["fail","wait"]}},required:["threshold","cooldownMs","mode"],additionalProperties:!1}},required:["contextCapacity","contextCeiling","reserveShare","smallShare","agingMs","queueDeadlineMs","breaker"],additionalProperties:!1},O={type:"object",properties:{providers:{type:"object",additionalProperties:{type:"integer",minimum:1}},tokens:{type:"object",additionalProperties:ce},scheduler:le,subagents:{type:"object",properties:{max:{type:"integer",minimum:0},hostAware:{type:"boolean"}},required:["max","hostAware"],additionalProperties:!1},adaptive:{type:"boolean"}},required:["providers","tokens","scheduler","subagents","adaptive"],additionalProperties:!1},ue={type:"object",properties:{ok:{type:"boolean"},errors:{type:"array",items:{type:"string"}},restartRequired:{type:"boolean"}},required:["ok","errors","restartRequired"],additionalProperties:!1},z={type:"object",properties:{},additionalProperties:!1},U={id:"request-concurrency-queue",methods:{status:{input:z,output:{type:"object",properties:{providers:{type:"array",items:ae},transitions:{type:"array",items:se},sessionDetails:{type:"array",items:ie},subagents:oe},required:["providers","transitions"],additionalProperties:!1}},config:{input:z,output:O},save:{input:O,output:ue}},events:{changed:{schema:z}}},k=[{percent:0,hue:145,saturation:60,lightness:28},{percent:100,hue:120,saturation:60,lightness:60},{percent:150,hue:60,saturation:85,lightness:70},{percent:200,hue:32,saturation:95,lightness:55},{percent:250,hue:12,saturation:90,lightness:68},{percent:300,hue:0,saturation:70,lightness:35},{percent:350,hue:-24,saturation:75,lightness:42},{percent:400,hue:-40,saturation:70,lightness:30}];function F(t){const n=Number.isFinite(t)?Math.max(0,t):0,s=k[k.length-1];if(n>=s.percent)return H(s);for(let r=1;r<k.length;r+=1){const a=k[r-1],o=k[r];if(n>o.percent)continue;const c=(n-a.percent)/(o.percent-a.percent);return`hsl(${Math.round(j(a.hue,o.hue,c))} ${Math.round(j(a.saturation,o.saturation,c))}% ${Math.round(j(a.lightness,o.lightness,c))}%)`}return H(s)}function H(t){return`hsl(${t.hue} ${t.saturation}% ${t.lightness}%)`}function j(t,n,s){return t+(n-t)*s}const de=5e3;function pe(t){const n=t.tokensCapacity,s=W(t.blocked),r=t.sessions??0;return{providerID:t.providerID,active:t.active,queued:t.queued,max:t.max,ceiling:t.ceiling,sessions:r,total:t.active+t.queued,slotLabel:`${t.active}/${t.max}`,queueLabel:t.queued>0?`+${t.queued}`:"",title:he(t,r,s),utilization:Q(t.utilization),demand:Q(t.demand),utilizationColor:F(t.active/t.max*100),demandColor:F(t.demand*100),tokensAvailable:t.tokensAvailable,tokensCapacity:t.tokensCapacity,tokensPausedUntil:t.tokensPausedUntil,blocked:t.blocked,blockedLabel:W(t.blocked),tokensLabel:n===0?"":`${E(t.tokensAvailable)} / ${E(n)}`,tokensColor:n===0?"":F((1-t.tokensAvailable/n)*300)}}function me(t){if(!t)return"";const n=t.split(/[\\/]/).filter(Boolean);return n[n.length-1]??""}function ge(t){return t.replace(/^ses_/,"").slice(0,8)}function he(t,n,s){const r=n===1?"1 session":`${n} sessions`,a=t.queued>0?` · ${t.queued} waiting${s===""?"":` on ${s}`}`:"",o=t.tokensCapacity>0?` · ${E(t.tokensAvailable)} new-context tokens`:"";return`${t.active} of ${t.max} slots in use by ${r}${a}${o}`}function W(t){const n=[];return t.slots>0&&n.push(`slots ${t.slots}`),t.context>0&&n.push(`context ${t.context}`),t.budget>0&&n.push(`budget ${t.budget}`),t.breaker>0&&n.push(`breaker ${t.breaker}`),t.draining>0&&n.push(`draining ${t.draining}`),n.join(" · ")}function fe(t){if(!t)return;const n=t.capacity<t.max?`${t.capacity} of ${t.max}`:String(t.max),s=t.calling??0;return{live:t.live,calling:s,queued:t.queued,max:t.max,capacity:t.capacity,label:`${t.live}/${n} live · ${s} calling${t.queued>0?` · ${t.queued} waiting`:""}`}}function E(t){const n=Number.isFinite(t)?Math.max(0,t):0;return n>=1e6?`${(n/1e6).toFixed(1).replace(/\.0$/,"")}m`:n>=1e3?`${Math.round(n/1e3)}k`:String(Math.round(n))}function ye(t){return t.providers.map(n=>pe(n))}const be=20;function ve(t,n=be){const s=new Map((t.sessionDetails??[]).map(r=>[r.sessionID,r]));return t.transitions.slice(-n).reverse().map(r=>qe(r,s.get(r.sessionID)))}function qe(t,n){const s=me(n?.directory),r=[n?.agent,s].filter(a=>!!a).join(" · ");return{time:Ce(t.timestamp),providerID:t.providerID,kind:t.kind,sessionID:t.sessionID,sessionLabel:n?.title?.trim()||ge(t.sessionID),sessionMeta:r,active:t.active,queued:t.queued}}function xe(t,n,s={}){const r=t(),a=s.refetchIntervalMs??de;let o=!1,c=0;const h=async()=>{const f=++c;let d;try{d=await r.status({},we(s.directory))}catch{!o&&f===c&&n(null);return}!o&&f===c&&n(d)};h();const m=r.events.on("changed",()=>{h()}),g=setInterval(()=>{h()},a);return()=>{o=!0,clearInterval(g),m()}}function we(t){return t===void 0?void 0:{location:{directory:t}}}function Q(t){return`${Math.round(t*100)}%`}function Ce(t){const n=new Date(t),s=r=>String(r).padStart(2,"0");return`${s(n.getHours())}:${s(n.getMinutes())}:${s(n.getSeconds())}`}var Se=e.template("<div class=request-concurrency-status-header aria-hidden=true><span>Provider</span><span>Active</span><span>Queued</span><span>Tokens</span><span>Util</span><span>Demand"),$e=e.template("<div class=request-concurrency-feed><div class=request-concurrency-feed-title>Recent activity"),ke=e.template("<div class=request-concurrency-status>"),_e=e.template("<div class=request-concurrency-status-unavailable>Status unavailable"),Ae=e.template('<div class=request-concurrency-status-row><span class=request-concurrency-status-provider></span><span class=request-concurrency-status-active><span></span><span class=request-concurrency-status-max></span></span><span class=request-concurrency-status-queued></span><span class=request-concurrency-status-tokens></span><span class=request-concurrency-status-utilization title="Utilization: active / max, capped at 100%"></span><span class=request-concurrency-status-demand title="Demand: (active + queued) / max">'),Pe=e.template("<div class=request-concurrency-subagents><span class=request-concurrency-subagents-label>Subagents</span><span class=request-concurrency-subagents-count>"),Me=e.template("<span class=request-concurrency-feed-session-meta>"),Le=e.template("<div class=request-concurrency-feed-row><span class=request-concurrency-feed-time></span><span></span><span class=request-concurrency-feed-provider></span><span class=request-concurrency-feed-session><span class=request-concurrency-feed-session-name></span></span><span class=request-concurrency-feed-counts>"),R=e.template("<span class=request-concurrency-field-help>"),Te=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input class=request-concurrency-input type=number>"),De=e.template('<label class="request-concurrency-field request-concurrency-field-inline"><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input type=checkbox>'),Ie=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><select class=request-concurrency-input>"),ze=e.template("<option>"),Fe=e.template("<div class=request-concurrency-config-title>Subagents"),je=e.template("<p class=request-concurrency-config-help>A guard on how many child sessions exist at once, for host load and cost — not a model-request limit. A child waiting for a tool holds a permit but no provider slot, so a ceiling near the provider's concurrency throttles the fan-out below what the provider allows and adds a second queue. Set it well above the provider maximum, or leave it at 0 to turn the guard off. The live and calling counts are reported either way when the guard is on."),Ee=e.template("<div class=request-concurrency-status-unavailable>"),Ne=e.template("<span class=request-concurrency-config-notice>"),Re=e.template("<div class=request-concurrency-config><p class=request-concurrency-config-intro>These settings decide how many requests may run at once and what happens when a provider is slow or stops answering. Save applies the change to the running server immediately. Only adding or removing a provider needs a restart.</p><div class=request-concurrency-config-title>Providers</div><p class=request-concurrency-config-help>How many requests may be sent to each provider at the same time. Anything beyond that waits in a queue rather than failing. Set this to the number of parallel requests your plan allows; a higher number is not served by the provider.</p><div class=request-concurrency-config-title>Token budget</div><p class=request-concurrency-config-help>Some providers cap how much brand-new text you may send in a short burst — text they have not already cached from earlier turns. This allowance refills over time. When it is used up, new requests wait for it to refill instead of being rejected.</p><div class=request-concurrency-config-title>Admission</div><p class=request-concurrency-config-help>These decide how many requests run at once and in what order waiting ones are served. The context cap matters most for big fan-outs: it counts the full prompt of every running request, not just the new text, so many long conversations at once can overload a provider even when the request count is within its limit.</p><div class=request-concurrency-config-title>Circuit breaker</div><p class=request-concurrency-config-help>If a provider accepts a request but never answers, every request would sit until it times out and the queue would keep growing. The breaker notices repeated silent failures and stops sending new requests for a while, so the queue stays small and you see the problem quickly.</p><div class=request-concurrency-config-title>Behaviour</div><div class=request-concurrency-config-actions><button type=button class=request-concurrency-save>"),Be=e.template("<div class=request-concurrency-config-group><div class=request-concurrency-config-subtitle>"),Oe=e.template("<div class=request-concurrency-config-error>"),Ue=e.template("<span class=request-concurrency-bar-items>"),He=e.template('<button type=button class=request-concurrency-bar title="Open concurrency details"aria-label="Open concurrency details"><span class=request-concurrency-bar-label>Concurrency'),We=e.template("<span class=request-concurrency-bar-muted>Status unavailable"),Qe=e.template("<span class=request-concurrency-bar-queue>"),Ve=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider></span><span class=request-concurrency-bar-slots>"),Ye=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider>subagents</span><span>"),Ge=e.template("<div class=request-concurrency-dialog><div class=request-concurrency-tabs role=tablist><button type=button role=tab>Queue</button><button type=button role=tab>Config"),Je=e.template("<div class=request-concurrency-status-unavailable>Settings unavailable");const Ke="Status unavailable",Xe={providers:[],transitions:[]};function B(t){if(t===null)return{unavailable:!0,rows:[],transitions:[]};const n=fe(t.subagents);return{unavailable:!1,rows:ye(t),transitions:ve(t),...n?{subagents:n}:{}}}function V(t){const n=()=>B(t.snapshot);return(()=>{var s=ke();return e.insert(s,e.createComponent(u.Show,{get when(){return!n().unavailable},get fallback(){return _e()},get children(){return[e.createComponent(u.Show,{get when(){return n().rows.length>0},get children(){return Se()}}),e.createComponent(u.For,{get each(){return n().rows},children:r=>(()=>{var a=Ae(),o=a.firstChild,c=o.nextSibling,h=c.firstChild,m=h.nextSibling,g=c.nextSibling,f=g.nextSibling,d=f.nextSibling,y=d.nextSibling;return e.insert(o,()=>r.providerID),e.insert(h,()=>r.active),e.insert(m,()=>` / ${r.max}`),e.insert(g,()=>r.queued),e.insert(f,(()=>{var i=e.memo(()=>r.tokensCapacity>0);return()=>i()?r.tokensLabel:"—"})()),e.insert(d,()=>r.utilization),e.insert(y,()=>r.demand),e.effect(i=>{var l=r.demandColor,v=r.providerID,A=`${r.active} of ${r.max} slots in use by ${r.sessions} ${r.sessions===1?"session":"sessions"}`,P=r.utilizationColor,w=r.demandColor,M=r.blockedLabel===""?`${r.queued} waiting`:`${r.queued} waiting (${r.blockedLabel})`,C=r.tokensColor,L=r.tokensCapacity>0?`${r.tokensAvailable} of ${r.tokensCapacity} new-context tokens available`:"No token budget configured",q=r.utilizationColor,T=r.demandColor;return l!==i.e&&e.setStyleProperty(a,"border-left-color",i.e=l),v!==i.t&&e.setAttribute(o,"title",i.t=v),A!==i.a&&e.setAttribute(c,"title",i.a=A),P!==i.o&&e.setStyleProperty(h,"color",i.o=P),w!==i.i&&e.setStyleProperty(g,"color",i.i=w),M!==i.n&&e.setAttribute(g,"title",i.n=M),C!==i.s&&e.setStyleProperty(f,"color",i.s=C),L!==i.h&&e.setAttribute(f,"title",i.h=L),q!==i.r&&e.setStyleProperty(d,"color",i.r=q),T!==i.d&&e.setStyleProperty(y,"color",i.d=T),i},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0}),a})()}),e.createComponent(u.Show,{get when(){return n().subagents},children:r=>(()=>{var a=Pe(),o=a.firstChild,c=o.nextSibling;return e.insert(c,()=>r().label),e.effect(()=>e.setAttribute(c,"title",`${r().live} child sessions hold a permit (${r().calling} are calling the model, the rest are running a tool); ${r().queued} launches wait for a permit, which is a separate limit from the model-request queue`)),a})()}),e.createComponent(u.Show,{get when(){return n().transitions.length>0},get children(){var r=$e();return r.firstChild,e.insert(r,e.createComponent(u.For,{get each(){return n().transitions},children:a=>(()=>{var o=Le(),c=o.firstChild,h=c.nextSibling,m=h.nextSibling,g=m.nextSibling,f=g.firstChild,d=g.nextSibling;return e.insert(c,()=>a.time),e.insert(h,()=>a.kind),e.insert(m,()=>a.providerID),e.insert(f,()=>a.sessionLabel),e.insert(g,e.createComponent(u.Show,{get when(){return a.sessionMeta!==""},get children(){var y=Me();return e.insert(y,()=>` · ${a.sessionMeta}`),y}}),null),e.insert(d,()=>`${a.active} active · ${a.queued} queued`),e.effect(y=>{var i=`request-concurrency-feed-kind is-${a.kind}`,l=a.providerID,v=a.sessionMeta===""?a.sessionID:`${a.sessionID} · ${a.sessionMeta}`;return i!==y.e&&e.className(h,y.e=i),l!==y.t&&e.setAttribute(m,"title",y.t=l),v!==y.a&&e.setAttribute(g,"title",y.a=v),y},{e:void 0,t:void 0,a:void 0}),o})()}),null),r}})]}})),s})()}function Y(t,n,s){if(n.length===0)return s;const[r,...a]=n,o={...t},c=o[r];return o[r]=a.length===0?s:Y(c,a,s),o}function b(t){return(()=>{var n=Te(),s=n.firstChild,r=s.firstChild,a=s.nextSibling;return e.insert(r,()=>t.label),e.insert(s,e.createComponent(u.Show,{get when(){return t.help},get children(){var o=R();return e.insert(o,()=>t.help),o}}),null),e.addEventListener(a,"input",o=>{const c=Number(o.currentTarget.value);Number.isFinite(c)&&t.onChange(c)}),e.effect(()=>e.setAttribute(a,"step",t.step??1)),e.effect(()=>a.value=String(t.value)),n})()}function G(t){return(()=>{var n=De(),s=n.firstChild,r=s.firstChild,a=s.nextSibling;return e.insert(r,()=>t.label),e.insert(s,e.createComponent(u.Show,{get when(){return t.help},get children(){var o=R();return e.insert(o,()=>t.help),o}}),null),e.addEventListener(a,"change",o=>t.onChange(o.currentTarget.checked)),e.effect(()=>a.checked=t.value),n})()}function Ze(t){return(()=>{var n=Ie(),s=n.firstChild,r=s.firstChild,a=s.nextSibling;return e.insert(r,()=>t.label),e.insert(s,e.createComponent(u.Show,{get when(){return t.help},get children(){var o=R();return e.insert(o,()=>t.help),o}}),null),e.addEventListener(a,"change",o=>t.onChange(o.currentTarget.value)),e.insert(a,e.createComponent(u.For,{get each(){return t.options},children:o=>(()=>{var c=ze();return e.insert(c,()=>o.label),e.effect(()=>c.value=o.value),c})()})),e.effect(()=>a.value=t.value),n})()}function N(t,n){return{...t,...n}}function J(t){return[Fe(),je(),e.createComponent(b,{label:"Live child sessions",help:"A runaway guard, not a concurrency limit. A child running a tool counts here but not against the provider. 0 turns the guard off.",get value(){return t.max},onChange:n=>t.onChange(N({max:t.max,hostAware:t.hostAware},{max:n}))}),e.createComponent(G,{label:"Host-aware ceiling",help:"When on, the machine's one-minute load average lowers the ceiling above, so a busy machine runs fewer child sessions than the maximum. When off, the maximum always applies.",get value(){return t.hostAware},onChange:n=>t.onChange(N({max:t.max,hostAware:t.hostAware},{hostAware:n}))})]}function K(t){const[n,s]=u.createSignal(null),[r,a]=u.createSignal([]),[o,c]=u.createSignal(""),[h,m]=u.createSignal(!1),[g,f]=u.createSignal(!0);u.createEffect(()=>{let i=!1;Promise.resolve().then(()=>t.client.config({})).then(l=>{i||(s(l),f(!1))}).catch(l=>{i||(a([`Could not read the plugin settings: ${l instanceof Error?l.message:String(l)}`]),f(!1))}),u.onCleanup(()=>{i=!0})});const d=(i,l)=>{const v=n();v&&(s(Y(v,i,l)),c(""))},y=async()=>{const i=n();if(i){m(!0),a([]),c("");try{const l=await t.client.save(i);l.ok?c(l.restartRequired?"Saved. Changing the provider set needs a restart.":"Saved and applied to the running server."):a(l.errors)}catch(l){a([`The save request failed: ${l instanceof Error?l.message:String(l)}`])}finally{m(!1)}}};return[e.createComponent(u.Show,{get when(){return n()},get fallback(){return(()=>{var i=Ee();return e.insert(i,()=>g()?"Loading settings…":"Settings unavailable"),i})()},children:i=>(()=>{var l=Re(),v=l.firstChild,A=v.nextSibling,P=A.nextSibling,w=P.nextSibling,M=w.nextSibling,C=M.nextSibling,L=C.nextSibling,q=L.nextSibling,T=q.nextSibling,S=T.nextSibling,D=S.nextSibling,I=D.firstChild;return e.insert(l,e.createComponent(u.For,{get each(){return Object.keys(i().providers)},children:p=>e.createComponent(b,{label:`${p} · max concurrent`,get value(){return i().providers[p]},onChange:x=>d(["providers",p],x)})}),w),e.insert(l,e.createComponent(u.For,{get each(){return Object.keys(i().tokens)},children:p=>(()=>{var x=Be(),ee=x.firstChild;return e.insert(ee,p),e.insert(x,e.createComponent(b,{label:"Capacity",help:"Brand-new tokens that may be sent in one burst before requests have to wait. Use the provider's documented burst allowance, for example 500000.",get value(){return i().tokens[p].capacity},onChange:$=>d(["tokens",p,"capacity"],$)}),null),e.insert(x,e.createComponent(b,{label:"Refill per minute",help:"How many brand-new tokens become available again each minute. Use the provider's documented refill rate, for example 500000 per minute.",get value(){return i().tokens[p].refillPerMinute},onChange:$=>d(["tokens",p,"refillPerMinute"],$)}),null),e.insert(x,e.createComponent(b,{label:"Safety factor",step:.05,help:"How much to over-estimate a request before charging it. 1.1 adds a 10% margin, so the allowance is reached slightly early rather than exceeded.",get value(){return i().tokens[p].safetyFactor},onChange:$=>d(["tokens",p,"safetyFactor"],$)}),null),x})()}),C),e.insert(l,e.createComponent(b,{label:"Context in flight (tokens)",help:"The sum of the full prompts of all running requests. A request waits if sending it would push that total over this number. 0 turns the cap off.",get value(){return i().scheduler.contextCapacity},onChange:p=>d(["scheduler","contextCapacity"],p)}),q),e.insert(l,e.createComponent(b,{label:"Context ceiling (tokens)",help:"The largest value the context cap above may grow back to after a stall. The cap shrinks only when the breaker opens, then grows back in quarters on clean completions. 0 keeps the cap fixed at the value above.",get value(){return i().scheduler.contextCeiling},onChange:p=>d(["scheduler","contextCeiling"],p)}),q),e.insert(l,e.createComponent(b,{label:"Reserve share",step:.05,help:"The part of the token budget that small requests may not use, so a large request is not blocked by a stream of small ones. 0.25 keeps 25% free.",get value(){return i().scheduler.reserveShare},onChange:p=>d(["scheduler","reserveShare"],p)}),q),e.insert(l,e.createComponent(b,{label:"Small-request share",step:.05,help:"A request whose cost is at most this fraction of the budget counts as small and must leave the reserve alone. Anything larger may use the reserve.",get value(){return i().scheduler.smallShare},onChange:p=>d(["scheduler","smallShare"],p)}),q),e.insert(l,e.createComponent(b,{label:"Queue aging (ms)",help:"After this many milliseconds a waiting request stops respecting the reserve, so a large request cannot be blocked forever by smaller ones.",get value(){return i().scheduler.agingMs},onChange:p=>d(["scheduler","agingMs"],p)}),q),e.insert(l,e.createComponent(b,{label:"Queue deadline (ms)",help:"How long a request may wait before the plugin gives up and reports a queue timeout. 0 waits as long as needed. Note that the client already abandons a request after 300000 ms, so a larger deadline never fires.",get value(){return i().scheduler.queueDeadlineMs},onChange:p=>d(["scheduler","queueDeadlineMs"],p)}),q),e.insert(l,e.createComponent(b,{label:"Stalls before opening",help:"How many failed attempts in a row, with no response at all, open the breaker. 3 gives the provider three chances.",get value(){return i().scheduler.breaker.threshold},onChange:p=>d(["scheduler","breaker","threshold"],p)}),S),e.insert(l,e.createComponent(b,{label:"Cooldown (ms)",help:"How long the breaker stays open. After this, one test request is allowed: if it succeeds the breaker closes, if it stalls the breaker reopens.",get value(){return i().scheduler.breaker.cooldownMs},onChange:p=>d(["scheduler","breaker","cooldownMs"],p)}),S),e.insert(l,e.createComponent(Ze,{label:"When open",help:"fail fast: new requests are rejected immediately, so you notice the outage now. wait: they stay queued and resume when the cooldown ends.",get value(){return i().scheduler.breaker.mode},options:[{value:"fail",label:"fail fast"},{value:"wait",label:"wait for cooldown"}],onChange:p=>d(["scheduler","breaker","mode"],p)}),S),e.insert(l,e.createComponent(J,{get max(){return i().subagents.max},get hostAware(){return i().subagents.hostAware},onChange:p=>{d(["subagents","hostAware"],p.hostAware),d(["subagents","max"],p.max)}}),S),e.insert(l,e.createComponent(G,{label:"Adaptive request width",help:"When on, the number of concurrent requests is halved after a capacity failure (a concurrency 429, a transport failure, or a 5xx) and raised by one after four successful requests in a row. A burst-protection 429 pauses the token bucket instead. When off, the provider maximum above is always used.",get value(){return i().adaptive},onChange:p=>d(["adaptive"],p)}),D),e.addEventListener(I,"click",y),e.insert(I,()=>h()?"Saving…":"Save"),e.insert(D,e.createComponent(u.Show,{get when(){return o()},get children(){var p=Ne();return e.insert(p,o),p}}),null),e.effect(()=>I.disabled=h()),l})()}),e.createComponent(u.For,{get each(){return r()},children:i=>(()=>{var l=Oe();return e.insert(l,i),l})()})]}function X(t){const n=()=>B(t.snapshot);return e.createComponent(u.Show,{get when(){return n().unavailable||n().rows.length>0},get children(){var s=He();return s.firstChild,e.addEventListener(s,"click",()=>t.onOpen()),e.insert(s,e.createComponent(u.Show,{get when(){return!n().unavailable},get fallback(){return We()},get children(){var r=Ue();return e.insert(r,e.createComponent(u.For,{get each(){return n().rows},children:a=>(()=>{var o=Ve(),c=o.firstChild,h=c.nextSibling;return e.insert(c,()=>a.providerID),e.insert(h,()=>a.slotLabel),e.insert(o,e.createComponent(u.Show,{get when(){return a.queued>0},get children(){var m=Qe();return e.insert(m,()=>a.queueLabel),e.effect(g=>{var f=a.demandColor,d=a.title;return f!==g.e&&e.setStyleProperty(m,"color",g.e=f),d!==g.t&&e.setAttribute(m,"title",g.t=d),g},{e:void 0,t:void 0}),m}}),null),e.effect(m=>{var g=a.utilizationColor,f=a.title;return g!==m.e&&e.setStyleProperty(h,"color",m.e=g),f!==m.t&&e.setAttribute(h,"title",m.t=f),m},{e:void 0,t:void 0}),o})()}),null),e.insert(r,e.createComponent(u.Show,{get when(){return n().subagents},children:a=>(()=>{var o=Ye(),c=o.firstChild,h=c.nextSibling;return e.insert(h,()=>a().label),e.effect(()=>e.setAttribute(o,"title",`${a().live} child sessions hold a permit (${a().calling} calling the model); ${a().queued} launches wait for a permit`)),o})()}),null),r}}),null),s}})}function et(t){const n=_.usePlugin(),[s,r]=u.createSignal("queue");return e.createComponent(n.ui.Dialog,{title:"Concurrency",size:"x-large",get children(){var a=Ge(),o=a.firstChild,c=o.firstChild,h=c.nextSibling;return e.addEventListener(c,"click",()=>r("queue")),e.addEventListener(h,"click",()=>r("config")),e.insert(a,e.createComponent(u.Show,{get when(){return s()==="queue"},get children(){return e.createComponent(V,{get snapshot(){return t.snapshot()}})}}),null),e.insert(a,e.createComponent(u.Show,{get when(){return s()==="config"},get children(){return e.createComponent(u.Show,{get when(){return t.client},get fallback(){return Je()},children:m=>e.createComponent(K,{get client(){return m()}})})}}),null),e.effect(m=>{var g=s()==="queue",f=`request-concurrency-tab${s()==="queue"?" is-active":""}`,d=s()==="config",y=`request-concurrency-tab${s()==="config"?" is-active":""}`;return g!==m.e&&e.setAttribute(c,"aria-selected",m.e=g),f!==m.t&&e.className(c,m.t=f),d!==m.a&&e.setAttribute(h,"aria-selected",m.a=d),y!==m.o&&e.className(h,m.o=y),m},{e:void 0,t:void 0,a:void 0,o:void 0}),a}})}function Z(){const t=_.usePlugin(),[n,s]=u.createSignal(Xe),[r,a]=u.createSignal(!1),[o,c]=u.createSignal(null);u.createEffect(()=>{const m=t.servers.list().map(d=>t.servers.get(d)),g=m.find(d=>d?.builtin)??m.find(Boolean);if(!g)return;c(g.client.rpc(U));const f=xe(()=>g.client.rpc(U),d=>{s(d),a(!0)});u.onCleanup(f)});const h=()=>{t.dialogs.open(()=>e.createComponent(et,{snapshot:n,get client(){return o()}}))};return e.createComponent(u.Show,{get when(){return r()},get children(){return e.createComponent(X,{get snapshot(){return n()},onOpen:h})}})}const tt=_.Plugin.define({setup(t){t.add(_.Slot,{at:"window.bottom",render:()=>e.createComponent(Z,{})}),t.add(_.Style,te+ne)}});exports.ConfigForm=K;exports.STATUS_UNAVAILABLE=Ke;exports.StatusBar=Z;exports.StatusBarBody=X;exports.StatusBody=V;exports.SubagentsSection=J;exports.default=tt;exports.editedSubagents=N;exports.statusBodyState=B;
