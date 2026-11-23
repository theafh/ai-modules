"use strict";Object.defineProperties(exports,{__esModule:{value:!0},[Symbol.toStringTag]:{value:"Module"}});const e=require("solid-js/web"),p=require("solid-js"),k=require("@opencode/plugin/gui"),ee=`
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

.request-concurrency-status-session {
  display: flex;
  gap: 8px;
  align-items: baseline;
  padding: 1px 8px 1px 26px;
  font-size: 11px;
  opacity: 0.72;
}

.request-concurrency-status-session-title {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.request-concurrency-status-session-meta {
  flex: none;
  white-space: nowrap;
  opacity: 0.85;
}

.request-concurrency-status-session-id {
  flex: none;
  margin-left: auto;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 10px;
  opacity: 0.55;
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
  grid-template-columns: auto 5em minmax(0, 0.8fr) minmax(0, 1fr) auto;
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
  opacity: 0.6;
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
`,te=`
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
`,ne={type:"object",properties:{slots:{type:"integer",minimum:0},context:{type:"integer",minimum:0},budget:{type:"integer",minimum:0},breaker:{type:"integer",minimum:0},draining:{type:"integer",minimum:0}},required:["slots","context","budget","breaker","draining"],additionalProperties:!1},re={type:"object",properties:{providerID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},ceiling:{type:"integer",minimum:0},sessions:{type:"integer",minimum:0},activeSessionIDs:{type:"array",items:{type:"string"}},utilization:{type:"number",minimum:0,maximum:1},demand:{type:"number",minimum:0},tokensAvailable:{type:"integer",minimum:0},tokensCapacity:{type:"integer",minimum:0},tokensPausedUntil:{type:"integer",minimum:0},blocked:ne,contextInFlight:{type:"integer",minimum:0},contextCapacity:{type:"integer",minimum:0},breaker:{type:"string",enum:["closed","open","half-open"]},breakerRetryAfterMs:{type:"integer",minimum:0},stalls:{type:"integer",minimum:0}},required:["providerID","active","queued","max","ceiling","utilization","demand","tokensAvailable","tokensCapacity","tokensPausedUntil","blocked","breaker","breakerRetryAfterMs","stalls"],additionalProperties:!1},se={type:"object",properties:{timestamp:{type:"integer",minimum:0},providerID:{type:"string"},kind:{type:"string",enum:["acquired","queued","released","dequeued"]},sessionID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0}},required:["timestamp","providerID","kind","sessionID","active","queued"],additionalProperties:!1},ie={type:"object",properties:{sessionID:{type:"string"},title:{type:"string"},agent:{type:"string"},directory:{type:"string"},parentID:{type:"string"}},required:["sessionID"],additionalProperties:!1},ae={type:"object",properties:{live:{type:"integer",minimum:0},calling:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},capacity:{type:"integer",minimum:0}},required:["live","calling","queued","max","capacity"],additionalProperties:!1},oe={type:"object",properties:{capacity:{type:"integer",minimum:1},refillPerMinute:{type:"integer",minimum:1},safetyFactor:{type:"number",minimum:.1,maximum:10}},required:["capacity","refillPerMinute","safetyFactor"],additionalProperties:!1},ce={type:"object",properties:{contextCapacity:{type:"integer",minimum:0},contextCeiling:{type:"integer",minimum:0},reserveShare:{type:"number",minimum:0,maximum:1},smallShare:{type:"number",minimum:0,maximum:1},agingMs:{type:"integer",minimum:0},queueDeadlineMs:{type:"integer",minimum:0},breaker:{type:"object",properties:{threshold:{type:"integer",minimum:1},cooldownMs:{type:"integer",minimum:0},mode:{type:"string",enum:["fail","wait"]}},required:["threshold","cooldownMs","mode"],additionalProperties:!1}},required:["contextCapacity","contextCeiling","reserveShare","smallShare","agingMs","queueDeadlineMs","breaker"],additionalProperties:!1},O={type:"object",properties:{providers:{type:"object",additionalProperties:{type:"integer",minimum:1}},tokens:{type:"object",additionalProperties:oe},scheduler:ce,subagents:{type:"object",properties:{max:{type:"integer",minimum:0},hostAware:{type:"boolean"}},required:["max","hostAware"],additionalProperties:!1},adaptive:{type:"boolean"}},required:["providers","tokens","scheduler","subagents","adaptive"],additionalProperties:!1},le={type:"object",properties:{ok:{type:"boolean"},errors:{type:"array",items:{type:"string"}},restartRequired:{type:"boolean"}},required:["ok","errors","restartRequired"],additionalProperties:!1},I={type:"object",properties:{},additionalProperties:!1},U={id:"request-concurrency-queue",methods:{status:{input:I,output:{type:"object",properties:{providers:{type:"array",items:re},transitions:{type:"array",items:se},sessionDetails:{type:"array",items:ie},subagents:ae},required:["providers","transitions"],additionalProperties:!1}},config:{input:I,output:O},save:{input:O,output:le}},events:{changed:{schema:I}}},S=[{percent:0,hue:145,saturation:60,lightness:28},{percent:100,hue:120,saturation:60,lightness:60},{percent:150,hue:60,saturation:85,lightness:70},{percent:200,hue:32,saturation:95,lightness:55},{percent:250,hue:12,saturation:90,lightness:68},{percent:300,hue:0,saturation:70,lightness:35},{percent:350,hue:-24,saturation:75,lightness:42},{percent:400,hue:-40,saturation:70,lightness:30}];function F(t){const n=Number.isFinite(t)?Math.max(0,t):0,i=S[S.length-1];if(n>=i.percent)return H(i);for(let s=1;s<S.length;s+=1){const r=S[s-1],a=S[s];if(n>a.percent)continue;const c=(n-r.percent)/(a.percent-r.percent);return`hsl(${Math.round(j(r.hue,a.hue,c))} ${Math.round(j(r.saturation,a.saturation,c))}% ${Math.round(j(r.lightness,a.lightness,c))}%)`}return H(i)}function H(t){return`hsl(${t.hue} ${t.saturation}% ${t.lightness}%)`}function j(t,n,i){return t+(n-t)*i}const ue=5e3;function de(t,n){const i=t.tokensCapacity,s=Q(t.blocked),r=t.sessions??0,a=(t.activeSessionIDs??[]).map(c=>pe(c,n?.get(c)));return{providerID:t.providerID,active:t.active,queued:t.queued,max:t.max,ceiling:t.ceiling,sessions:r,total:t.active+t.queued,slotLabel:`${t.active}/${t.max}`,queueLabel:t.queued>0?`+${t.queued}`:"",title:ge(t,r,s),sessionRows:a,utilization:W(t.utilization),demand:W(t.demand),utilizationColor:F(t.utilization*100),demandColor:F(t.demand*100),tokensAvailable:t.tokensAvailable,tokensCapacity:t.tokensCapacity,tokensPausedUntil:t.tokensPausedUntil,blocked:t.blocked,blockedLabel:Q(t.blocked),tokensLabel:i===0?"":`${R(t.tokensAvailable)} / ${R(i)}`,tokensColor:i===0?"":F(t.tokensAvailable/i*100)}}function pe(t,n){const i=me(n?.directory),s=[n?.agent,i].filter(r=>!!r).join(" · ");return{sessionID:t,shortID:t.replace(/^ses_/,"").slice(0,8),title:n?.title?.trim()||"Untitled session",meta:s}}function me(t){if(!t)return"";const n=t.split(/[\\/]/).filter(Boolean);return n[n.length-1]??""}function ge(t,n,i){const s=n===1?"1 session":`${n} sessions`,r=t.queued>0?` · ${t.queued} waiting${i===""?"":` on ${i}`}`:"",a=t.tokensCapacity>0?` · ${R(t.tokensAvailable)} new-context tokens`:"";return`${t.active} of ${t.max} slots in use by ${s}${r}${a}`}function Q(t){const n=[];return t.slots>0&&n.push(`slots ${t.slots}`),t.context>0&&n.push(`context ${t.context}`),t.budget>0&&n.push(`budget ${t.budget}`),t.breaker>0&&n.push(`breaker ${t.breaker}`),t.draining>0&&n.push(`draining ${t.draining}`),n.join(" · ")}function he(t){if(!t)return;const n=t.capacity<t.max?`${t.capacity} of ${t.max}`:String(t.max),i=t.calling??0;return{live:t.live,calling:i,queued:t.queued,max:t.max,capacity:t.capacity,label:`${t.live}/${n} live · ${i} calling${t.queued>0?` · ${t.queued} waiting`:""}`}}function R(t){const n=Number.isFinite(t)?Math.max(0,t):0;return n>=1e6?`${(n/1e6).toFixed(1).replace(/\.0$/,"")}m`:n>=1e3?`${Math.round(n/1e3)}k`:String(Math.round(n))}function fe(t){const n=new Map((t.sessionDetails??[]).map(i=>[i.sessionID,i]));return t.providers.map(i=>de(i,n))}const ye=20;function be(t,n=ye){return t.transitions.slice(-n).reverse().map(ve)}function ve(t){return{time:we(t.timestamp),providerID:t.providerID,kind:t.kind,sessionID:t.sessionID,active:t.active,queued:t.queued}}function qe(t,n,i={}){const s=t(),r=i.refetchIntervalMs??ue;let a=!1,c=0;const g=async()=>{const f=++c;let l;try{l=await s.status({},xe(i.directory))}catch{!a&&f===c&&n(null);return}!a&&f===c&&n(l)};g();const d=s.events.on("changed",()=>{g()}),h=setInterval(()=>{g()},r);return()=>{a=!0,clearInterval(h),d()}}function xe(t){return t===void 0?void 0:{location:{directory:t}}}function W(t){return`${Math.round(t*100)}%`}function we(t){const n=new Date(t),i=s=>String(s).padStart(2,"0");return`${i(n.getHours())}:${i(n.getMinutes())}:${i(n.getSeconds())}`}var $e=e.template("<div class=request-concurrency-status-header aria-hidden=true><span>Provider</span><span>Active</span><span>Queued</span><span>Tokens</span><span>Util</span><span>Demand"),Ce=e.template("<div class=request-concurrency-feed><div class=request-concurrency-feed-title>Recent activity"),Se=e.template("<div class=request-concurrency-status>"),ke=e.template("<div class=request-concurrency-status-unavailable>Status unavailable"),_e=e.template('<div class=request-concurrency-status-row><span class=request-concurrency-status-provider></span><span class=request-concurrency-status-active><span></span><span class=request-concurrency-status-max></span></span><span class=request-concurrency-status-queued></span><span class=request-concurrency-status-tokens></span><span class=request-concurrency-status-utilization title="Utilization: active / max"></span><span class=request-concurrency-status-demand title="Demand: (active + queued) / max">'),Ae=e.template("<span class=request-concurrency-status-session-meta>"),Pe=e.template("<div class=request-concurrency-status-session><span class=request-concurrency-status-session-title></span><span class=request-concurrency-status-session-id>"),Me=e.template("<div class=request-concurrency-subagents><span class=request-concurrency-subagents-label>Subagents</span><span class=request-concurrency-subagents-count>"),Le=e.template("<div class=request-concurrency-feed-row><span class=request-concurrency-feed-time></span><span></span><span class=request-concurrency-feed-provider></span><span class=request-concurrency-feed-session></span><span class=request-concurrency-feed-counts>"),E=e.template("<span class=request-concurrency-field-help>"),Te=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input class=request-concurrency-input type=number>"),ze=e.template('<label class="request-concurrency-field request-concurrency-field-inline"><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input type=checkbox>'),De=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><select class=request-concurrency-input>"),Ie=e.template("<option>"),Fe=e.template("<div class=request-concurrency-status-unavailable>"),je=e.template("<span class=request-concurrency-config-notice>"),Re=e.template("<div class=request-concurrency-config><p class=request-concurrency-config-intro>These settings decide how many requests may run at once and what happens when a provider is slow or stops answering. Save applies the change to the running server immediately. Only adding or removing a provider needs a restart.</p><div class=request-concurrency-config-title>Providers</div><p class=request-concurrency-config-help>How many requests may be sent to each provider at the same time. Anything beyond that waits in a queue rather than failing. Set this to the number of parallel requests your plan allows; a higher number is not served by the provider.</p><div class=request-concurrency-config-title>Token budget</div><p class=request-concurrency-config-help>Some providers cap how much brand-new text you may send in a short burst — text they have not already cached from earlier turns. This allowance refills over time. When it is used up, new requests wait for it to refill instead of being rejected.</p><div class=request-concurrency-config-title>Admission</div><p class=request-concurrency-config-help>These decide how many requests run at once and in what order waiting ones are served. The context cap matters most for big fan-outs: it counts the full prompt of every running request, not just the new text, so many long conversations at once can overload a provider even when the request count is within its limit.</p><div class=request-concurrency-config-title>Circuit breaker</div><p class=request-concurrency-config-help>If a provider accepts a request but never answers, every request would sit until it times out and the queue would keep growing. The breaker notices repeated silent failures and stops sending new requests for a while, so the queue stays small and you see the problem quickly.</p><div class=request-concurrency-config-title>Subagents</div><p class=request-concurrency-config-help>A guard on how many child sessions exist at once, for host load and cost — not a model-request limit. A child waiting for a tool holds a permit but no provider slot, so a ceiling near the provider's concurrency throttles the fan-out below what the provider allows and adds a second queue. Set it well above the provider maximum, or leave it at 0 to turn the guard off. The live and calling counts are reported either way when the guard is on.</p><div class=request-concurrency-config-title>Behaviour</div><div class=request-concurrency-config-actions><button type=button class=request-concurrency-save>"),Ee=e.template("<div class=request-concurrency-config-group><div class=request-concurrency-config-subtitle>"),Ne=e.template("<div class=request-concurrency-config-error>"),Be=e.template("<span class=request-concurrency-bar-items>"),Oe=e.template('<button type=button class=request-concurrency-bar title="Open concurrency details"aria-label="Open concurrency details"><span class=request-concurrency-bar-label>Concurrency'),Ue=e.template("<span class=request-concurrency-bar-muted>Status unavailable"),He=e.template("<span class=request-concurrency-bar-queue>"),Qe=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider></span><span class=request-concurrency-bar-slots>"),We=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider>subagents</span><span>"),Ve=e.template("<div class=request-concurrency-dialog><div class=request-concurrency-tabs role=tablist><button type=button role=tab>Queue</button><button type=button role=tab>Config"),Ye=e.template("<div class=request-concurrency-status-unavailable>Settings unavailable");const Ge="Status unavailable",Je={providers:[],transitions:[]};function N(t){if(t===null)return{unavailable:!0,rows:[],transitions:[]};const n=he(t.subagents);return{unavailable:!1,rows:fe(t),transitions:be(t),...n?{subagents:n}:{}}}function V(t){const n=()=>N(t.snapshot);return(()=>{var i=Se();return e.insert(i,e.createComponent(p.Show,{get when(){return!n().unavailable},get fallback(){return ke()},get children(){return[e.createComponent(p.Show,{get when(){return n().rows.length>0},get children(){return $e()}}),e.createComponent(p.For,{get each(){return n().rows},children:s=>[(()=>{var r=_e(),a=r.firstChild,c=a.nextSibling,g=c.firstChild,d=g.nextSibling,h=c.nextSibling,f=h.nextSibling,l=f.nextSibling,b=l.nextSibling;return e.insert(a,()=>s.providerID),e.insert(g,()=>s.active),e.insert(d,()=>` / ${s.max}`),e.insert(h,()=>s.queued),e.insert(f,(()=>{var o=e.memo(()=>s.tokensCapacity>0);return()=>o()?s.tokensLabel:"—"})()),e.insert(l,()=>s.utilization),e.insert(b,()=>s.demand),e.effect(o=>{var u=s.demandColor,q=s.providerID,_=`${s.active} of ${s.max} slots in use by ${s.sessions} ${s.sessions===1?"session":"sessions"}`,A=s.utilizationColor,w=s.demandColor,P=s.blockedLabel===""?`${s.queued} waiting`:`${s.queued} waiting (${s.blockedLabel})`,$=s.tokensColor,M=s.tokensCapacity>0?`${s.tokensAvailable} of ${s.tokensCapacity} new-context tokens available`:"No token budget configured",v=s.utilizationColor,L=s.demandColor;return u!==o.e&&e.setStyleProperty(r,"border-left-color",o.e=u),q!==o.t&&e.setAttribute(a,"title",o.t=q),_!==o.a&&e.setAttribute(c,"title",o.a=_),A!==o.o&&e.setStyleProperty(g,"color",o.o=A),w!==o.i&&e.setStyleProperty(h,"color",o.i=w),P!==o.n&&e.setAttribute(h,"title",o.n=P),$!==o.s&&e.setStyleProperty(f,"color",o.s=$),M!==o.h&&e.setAttribute(f,"title",o.h=M),v!==o.r&&e.setStyleProperty(l,"color",o.r=v),L!==o.d&&e.setStyleProperty(b,"color",o.d=L),o},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0}),r})(),e.createComponent(p.For,{get each(){return s.sessionRows},children:r=>(()=>{var a=Pe(),c=a.firstChild,g=c.nextSibling;return e.insert(c,()=>`↳ ${r.title}`),e.insert(a,e.createComponent(p.Show,{get when(){return r.meta!==""},get children(){var d=Ae();return e.insert(d,()=>r.meta),d}}),g),e.insert(g,()=>r.shortID),e.effect(()=>e.setAttribute(a,"title",r.sessionID)),a})()})]}),e.createComponent(p.Show,{get when(){return n().subagents},children:s=>(()=>{var r=Me(),a=r.firstChild,c=a.nextSibling;return e.insert(c,()=>s().label),e.effect(()=>e.setAttribute(c,"title",`${s().live} child sessions hold a permit (${s().calling} are calling the model, the rest are running a tool); ${s().queued} launches wait for a permit, which is a separate limit from the model-request queue`)),r})()}),e.createComponent(p.Show,{get when(){return n().transitions.length>0},get children(){var s=Ce();return s.firstChild,e.insert(s,e.createComponent(p.For,{get each(){return n().transitions},children:r=>(()=>{var a=Le(),c=a.firstChild,g=c.nextSibling,d=g.nextSibling,h=d.nextSibling,f=h.nextSibling;return e.insert(c,()=>r.time),e.insert(g,()=>r.kind),e.insert(d,()=>r.providerID),e.insert(h,()=>r.sessionID),e.insert(f,()=>`${r.active} active · ${r.queued} queued`),e.effect(l=>{var b=`request-concurrency-feed-kind is-${r.kind}`,o=r.providerID,u=r.sessionID;return b!==l.e&&e.className(g,l.e=b),o!==l.t&&e.setAttribute(d,"title",l.t=o),u!==l.a&&e.setAttribute(h,"title",l.a=u),l},{e:void 0,t:void 0,a:void 0}),a})()}),null),s}})]}})),i})()}function Y(t,n,i){if(n.length===0)return i;const[s,...r]=n,a={...t},c=a[s];return a[s]=r.length===0?i:Y(c,r,i),a}function y(t){return(()=>{var n=Te(),i=n.firstChild,s=i.firstChild,r=i.nextSibling;return e.insert(s,()=>t.label),e.insert(i,e.createComponent(p.Show,{get when(){return t.help},get children(){var a=E();return e.insert(a,()=>t.help),a}}),null),e.addEventListener(r,"input",a=>{const c=Number(a.currentTarget.value);Number.isFinite(c)&&t.onChange(c)}),e.effect(()=>e.setAttribute(r,"step",t.step??1)),e.effect(()=>r.value=String(t.value)),n})()}function Ke(t){return(()=>{var n=ze(),i=n.firstChild,s=i.firstChild,r=i.nextSibling;return e.insert(s,()=>t.label),e.insert(i,e.createComponent(p.Show,{get when(){return t.help},get children(){var a=E();return e.insert(a,()=>t.help),a}}),null),e.addEventListener(r,"change",a=>t.onChange(a.currentTarget.checked)),e.effect(()=>r.checked=t.value),n})()}function Xe(t){return(()=>{var n=De(),i=n.firstChild,s=i.firstChild,r=i.nextSibling;return e.insert(s,()=>t.label),e.insert(i,e.createComponent(p.Show,{get when(){return t.help},get children(){var a=E();return e.insert(a,()=>t.help),a}}),null),e.addEventListener(r,"change",a=>t.onChange(a.currentTarget.value)),e.insert(r,e.createComponent(p.For,{get each(){return t.options},children:a=>(()=>{var c=Ie();return e.insert(c,()=>a.label),e.effect(()=>c.value=a.value),c})()})),e.effect(()=>r.value=t.value),n})()}function G(t){const[n,i]=p.createSignal(null),[s,r]=p.createSignal([]),[a,c]=p.createSignal(""),[g,d]=p.createSignal(!1),[h,f]=p.createSignal(!0);p.createEffect(()=>{let o=!1;Promise.resolve().then(()=>t.client.config({})).then(u=>{o||(i(u),f(!1))}).catch(u=>{o||(r([`Could not read the plugin settings: ${u instanceof Error?u.message:String(u)}`]),f(!1))}),p.onCleanup(()=>{o=!0})});const l=(o,u)=>{const q=n();q&&(i(Y(q,o,u)),c(""))},b=async()=>{const o=n();if(o){d(!0),r([]),c("");try{const u=await t.client.save(o);u.ok?c(u.restartRequired?"Saved. Changing the provider set needs a restart.":"Saved and applied to the running server."):r(u.errors)}catch(u){r([`The save request failed: ${u instanceof Error?u.message:String(u)}`])}finally{d(!1)}}};return[e.createComponent(p.Show,{get when(){return n()},get fallback(){return(()=>{var o=Fe();return e.insert(o,()=>h()?"Loading settings…":"Settings unavailable"),o})()},children:o=>(()=>{var u=Re(),q=u.firstChild,_=q.nextSibling,A=_.nextSibling,w=A.nextSibling,P=w.nextSibling,$=P.nextSibling,M=$.nextSibling,v=M.nextSibling,L=v.nextSibling,T=L.nextSibling,X=T.nextSibling,B=X.nextSibling,z=B.nextSibling,D=z.firstChild;return e.insert(u,e.createComponent(p.For,{get each(){return Object.keys(o().providers)},children:m=>e.createComponent(y,{label:`${m} · max concurrent`,get value(){return o().providers[m]},onChange:x=>l(["providers",m],x)})}),w),e.insert(u,e.createComponent(p.For,{get each(){return Object.keys(o().tokens)},children:m=>(()=>{var x=Ee(),Z=x.firstChild;return e.insert(Z,m),e.insert(x,e.createComponent(y,{label:"Capacity",help:"Brand-new tokens that may be sent in one burst before requests have to wait. Use the provider's documented burst allowance, for example 500000.",get value(){return o().tokens[m].capacity},onChange:C=>l(["tokens",m,"capacity"],C)}),null),e.insert(x,e.createComponent(y,{label:"Refill per minute",help:"How many brand-new tokens become available again each minute. Use the provider's documented refill rate, for example 500000 per minute.",get value(){return o().tokens[m].refillPerMinute},onChange:C=>l(["tokens",m,"refillPerMinute"],C)}),null),e.insert(x,e.createComponent(y,{label:"Safety factor",step:.05,help:"How much to over-estimate a request before charging it. 1.1 adds a 10% margin, so the allowance is reached slightly early rather than exceeded.",get value(){return o().tokens[m].safetyFactor},onChange:C=>l(["tokens",m,"safetyFactor"],C)}),null),x})()}),$),e.insert(u,e.createComponent(y,{label:"Context in flight (tokens)",help:"The sum of the full prompts of all running requests. A request waits if sending it would push that total over this number. 0 turns the cap off.",get value(){return o().scheduler.contextCapacity},onChange:m=>l(["scheduler","contextCapacity"],m)}),v),e.insert(u,e.createComponent(y,{label:"Context ceiling (tokens)",help:"The largest value the context cap above may grow back to after a stall. The cap shrinks only when the breaker opens, then grows back in quarters on clean completions. 0 keeps the cap fixed at the value above.",get value(){return o().scheduler.contextCeiling},onChange:m=>l(["scheduler","contextCeiling"],m)}),v),e.insert(u,e.createComponent(y,{label:"Reserve share",step:.05,help:"The part of the token budget that small requests may not use, so a large request is not blocked by a stream of small ones. 0.25 keeps 25% free.",get value(){return o().scheduler.reserveShare},onChange:m=>l(["scheduler","reserveShare"],m)}),v),e.insert(u,e.createComponent(y,{label:"Small-request share",step:.05,help:"A request whose cost is at most this fraction of the budget counts as small and must leave the reserve alone. Anything larger may use the reserve.",get value(){return o().scheduler.smallShare},onChange:m=>l(["scheduler","smallShare"],m)}),v),e.insert(u,e.createComponent(y,{label:"Queue aging (ms)",help:"After this many milliseconds a waiting request stops respecting the reserve, so a large request cannot be blocked forever by smaller ones.",get value(){return o().scheduler.agingMs},onChange:m=>l(["scheduler","agingMs"],m)}),v),e.insert(u,e.createComponent(y,{label:"Queue deadline (ms)",help:"How long a request may wait before the plugin gives up and reports a queue timeout. 0 waits as long as needed. Note that the client already abandons a request after 300000 ms, so a larger deadline never fires.",get value(){return o().scheduler.queueDeadlineMs},onChange:m=>l(["scheduler","queueDeadlineMs"],m)}),v),e.insert(u,e.createComponent(y,{label:"Stalls before opening",help:"How many failed attempts in a row, with no response at all, open the breaker. 3 gives the provider three chances.",get value(){return o().scheduler.breaker.threshold},onChange:m=>l(["scheduler","breaker","threshold"],m)}),T),e.insert(u,e.createComponent(y,{label:"Cooldown (ms)",help:"How long the breaker stays open. After this, one test request is allowed: if it succeeds the breaker closes, if it stalls the breaker reopens.",get value(){return o().scheduler.breaker.cooldownMs},onChange:m=>l(["scheduler","breaker","cooldownMs"],m)}),T),e.insert(u,e.createComponent(Xe,{label:"When open",help:"fail fast: new requests are rejected immediately, so you notice the outage now. wait: they stay queued and resume when the cooldown ends.",get value(){return o().scheduler.breaker.mode},options:[{value:"fail",label:"fail fast"},{value:"wait",label:"wait for cooldown"}],onChange:m=>l(["scheduler","breaker","mode"],m)}),T),e.insert(u,e.createComponent(y,{label:"Live child sessions",help:"A runaway guard, not a concurrency limit. A child running a tool counts here but not against the provider. 0 turns the guard off.",get value(){return o().subagents.max},onChange:m=>l(["subagents","max"],m)}),B),e.insert(u,e.createComponent(Ke,{label:"Adaptive request width",help:"When on, the number of concurrent requests is halved after a capacity failure (a concurrency 429, a transport failure, or a 5xx) and raised by one after four successful requests in a row. A burst-protection 429 pauses the token bucket instead. When off, the provider maximum above is always used.",get value(){return o().adaptive},onChange:m=>l(["adaptive"],m)}),z),e.addEventListener(D,"click",b),e.insert(D,()=>g()?"Saving…":"Save"),e.insert(z,e.createComponent(p.Show,{get when(){return a()},get children(){var m=je();return e.insert(m,a),m}}),null),e.effect(()=>D.disabled=g()),u})()}),e.createComponent(p.For,{get each(){return s()},children:o=>(()=>{var u=Ne();return e.insert(u,o),u})()})]}function J(t){const n=()=>N(t.snapshot);return e.createComponent(p.Show,{get when(){return n().unavailable||n().rows.length>0},get children(){var i=Oe();return i.firstChild,e.addEventListener(i,"click",()=>t.onOpen()),e.insert(i,e.createComponent(p.Show,{get when(){return!n().unavailable},get fallback(){return Ue()},get children(){var s=Be();return e.insert(s,e.createComponent(p.For,{get each(){return n().rows},children:r=>(()=>{var a=Qe(),c=a.firstChild,g=c.nextSibling;return e.insert(c,()=>r.providerID),e.insert(g,()=>r.slotLabel),e.insert(a,e.createComponent(p.Show,{get when(){return r.queued>0},get children(){var d=He();return e.insert(d,()=>r.queueLabel),e.effect(h=>{var f=r.demandColor,l=r.title;return f!==h.e&&e.setStyleProperty(d,"color",h.e=f),l!==h.t&&e.setAttribute(d,"title",h.t=l),h},{e:void 0,t:void 0}),d}}),null),e.effect(d=>{var h=r.utilizationColor,f=r.title;return h!==d.e&&e.setStyleProperty(g,"color",d.e=h),f!==d.t&&e.setAttribute(g,"title",d.t=f),d},{e:void 0,t:void 0}),a})()}),null),e.insert(s,e.createComponent(p.Show,{get when(){return n().subagents},children:r=>(()=>{var a=We(),c=a.firstChild,g=c.nextSibling;return e.insert(g,()=>r().label),e.effect(()=>e.setAttribute(a,"title",`${r().live} child sessions hold a permit (${r().calling} calling the model); ${r().queued} launches wait for a permit`)),a})()}),null),s}}),null),i}})}function Ze(t){const n=k.usePlugin(),[i,s]=p.createSignal("queue");return e.createComponent(n.ui.Dialog,{title:"Concurrency",size:"x-large",get children(){var r=Ve(),a=r.firstChild,c=a.firstChild,g=c.nextSibling;return e.addEventListener(c,"click",()=>s("queue")),e.addEventListener(g,"click",()=>s("config")),e.insert(r,e.createComponent(p.Show,{get when(){return i()==="queue"},get children(){return e.createComponent(V,{get snapshot(){return t.snapshot()}})}}),null),e.insert(r,e.createComponent(p.Show,{get when(){return i()==="config"},get children(){return e.createComponent(p.Show,{get when(){return t.client},get fallback(){return Ye()},children:d=>e.createComponent(G,{get client(){return d()}})})}}),null),e.effect(d=>{var h=i()==="queue",f=`request-concurrency-tab${i()==="queue"?" is-active":""}`,l=i()==="config",b=`request-concurrency-tab${i()==="config"?" is-active":""}`;return h!==d.e&&e.setAttribute(c,"aria-selected",d.e=h),f!==d.t&&e.className(c,d.t=f),l!==d.a&&e.setAttribute(g,"aria-selected",d.a=l),b!==d.o&&e.className(g,d.o=b),d},{e:void 0,t:void 0,a:void 0,o:void 0}),r}})}function K(){const t=k.usePlugin(),[n,i]=p.createSignal(Je),[s,r]=p.createSignal(!1),[a,c]=p.createSignal(null);p.createEffect(()=>{const d=t.servers.list().map(l=>t.servers.get(l)),h=d.find(l=>l?.builtin)??d.find(Boolean);if(!h)return;c(h.client.rpc(U));const f=qe(()=>h.client.rpc(U),l=>{i(l),r(!0)});p.onCleanup(f)});const g=()=>{t.dialogs.open(()=>e.createComponent(Ze,{snapshot:n,get client(){return a()}}))};return e.createComponent(p.Show,{get when(){return s()},get children(){return e.createComponent(J,{get snapshot(){return n()},onOpen:g})}})}const et=k.Plugin.define({setup(t){t.add(k.Slot,{at:"window.bottom",render:()=>e.createComponent(K,{})}),t.add(k.Style,ee+te)}});exports.ConfigForm=G;exports.STATUS_UNAVAILABLE=Ge;exports.StatusBar=K;exports.StatusBarBody=J;exports.StatusBody=V;exports.default=et;exports.statusBodyState=N;
