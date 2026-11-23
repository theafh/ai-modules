"use strict";Object.defineProperties(exports,{__esModule:{value:!0},[Symbol.toStringTag]:{value:"Module"}});const e=require("solid-js/web"),u=require("solid-js"),k=require("@opencode/plugin/gui"),ee=`
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
`,ne={type:"object",properties:{slots:{type:"integer",minimum:0},context:{type:"integer",minimum:0},budget:{type:"integer",minimum:0},breaker:{type:"integer",minimum:0},draining:{type:"integer",minimum:0}},required:["slots","context","budget","breaker","draining"],additionalProperties:!1},re={type:"object",properties:{providerID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},ceiling:{type:"integer",minimum:0},sessions:{type:"integer",minimum:0},activeSessionIDs:{type:"array",items:{type:"string"}},utilization:{type:"number",minimum:0,maximum:1},demand:{type:"number",minimum:0},tokensAvailable:{type:"integer",minimum:0},tokensCapacity:{type:"integer",minimum:0},tokensPausedUntil:{type:"integer",minimum:0},blocked:ne,contextInFlight:{type:"integer",minimum:0},contextCapacity:{type:"integer",minimum:0},breaker:{type:"string",enum:["closed","open","half-open"]},breakerRetryAfterMs:{type:"integer",minimum:0},stalls:{type:"integer",minimum:0}},required:["providerID","active","queued","max","ceiling","utilization","demand","tokensAvailable","tokensCapacity","tokensPausedUntil","blocked","breaker","breakerRetryAfterMs","stalls"],additionalProperties:!1},se={type:"object",properties:{timestamp:{type:"integer",minimum:0},providerID:{type:"string"},kind:{type:"string",enum:["acquired","queued","released","dequeued"]},sessionID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0}},required:["timestamp","providerID","kind","sessionID","active","queued"],additionalProperties:!1},ie={type:"object",properties:{sessionID:{type:"string"},title:{type:"string"},agent:{type:"string"},directory:{type:"string"},parentID:{type:"string"}},required:["sessionID"],additionalProperties:!1},ae={type:"object",properties:{live:{type:"integer",minimum:0},calling:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},capacity:{type:"integer",minimum:0}},required:["live","calling","queued","max","capacity"],additionalProperties:!1},oe={type:"object",properties:{capacity:{type:"integer",minimum:1},refillPerMinute:{type:"integer",minimum:1},safetyFactor:{type:"number",minimum:.1,maximum:10}},required:["capacity","refillPerMinute","safetyFactor"],additionalProperties:!1},ce={type:"object",properties:{contextCapacity:{type:"integer",minimum:0},contextCeiling:{type:"integer",minimum:0},reserveShare:{type:"number",minimum:0,maximum:1},smallShare:{type:"number",minimum:0,maximum:1},agingMs:{type:"integer",minimum:0},queueDeadlineMs:{type:"integer",minimum:0},breaker:{type:"object",properties:{threshold:{type:"integer",minimum:1},cooldownMs:{type:"integer",minimum:0},mode:{type:"string",enum:["fail","wait"]}},required:["threshold","cooldownMs","mode"],additionalProperties:!1}},required:["contextCapacity","contextCeiling","reserveShare","smallShare","agingMs","queueDeadlineMs","breaker"],additionalProperties:!1},O={type:"object",properties:{providers:{type:"object",additionalProperties:{type:"integer",minimum:1}},tokens:{type:"object",additionalProperties:oe},scheduler:ce,subagents:{type:"object",properties:{max:{type:"integer",minimum:0},hostAware:{type:"boolean"}},required:["max","hostAware"],additionalProperties:!1},adaptive:{type:"boolean"}},required:["providers","tokens","scheduler","subagents","adaptive"],additionalProperties:!1},le={type:"object",properties:{ok:{type:"boolean"},errors:{type:"array",items:{type:"string"}},restartRequired:{type:"boolean"}},required:["ok","errors","restartRequired"],additionalProperties:!1},z={type:"object",properties:{},additionalProperties:!1},U={id:"request-concurrency-queue",methods:{status:{input:z,output:{type:"object",properties:{providers:{type:"array",items:re},transitions:{type:"array",items:se},sessionDetails:{type:"array",items:ie},subagents:ae},required:["providers","transitions"],additionalProperties:!1}},config:{input:z,output:O},save:{input:O,output:le}},events:{changed:{schema:z}}},S=[{percent:0,hue:145,saturation:60,lightness:28},{percent:100,hue:120,saturation:60,lightness:60},{percent:150,hue:60,saturation:85,lightness:70},{percent:200,hue:32,saturation:95,lightness:55},{percent:250,hue:12,saturation:90,lightness:68},{percent:300,hue:0,saturation:70,lightness:35},{percent:350,hue:-24,saturation:75,lightness:42},{percent:400,hue:-40,saturation:70,lightness:30}];function F(t){const n=Number.isFinite(t)?Math.max(0,t):0,i=S[S.length-1];if(n>=i.percent)return H(i);for(let r=1;r<S.length;r+=1){const s=S[r-1],o=S[r];if(n>o.percent)continue;const c=(n-s.percent)/(o.percent-s.percent);return`hsl(${Math.round(j(s.hue,o.hue,c))} ${Math.round(j(s.saturation,o.saturation,c))}% ${Math.round(j(s.lightness,o.lightness,c))}%)`}return H(i)}function H(t){return`hsl(${t.hue} ${t.saturation}% ${t.lightness}%)`}function j(t,n,i){return t+(n-t)*i}const ue=5e3;function de(t){const n=t.tokensCapacity,i=Q(t.blocked),r=t.sessions??0;return{providerID:t.providerID,active:t.active,queued:t.queued,max:t.max,ceiling:t.ceiling,sessions:r,total:t.active+t.queued,slotLabel:`${t.active}/${t.max}`,queueLabel:t.queued>0?`+${t.queued}`:"",title:ge(t,r,i),utilization:W(t.utilization),demand:W(t.demand),utilizationColor:F(t.active/t.max*100),demandColor:F(t.demand*100),tokensAvailable:t.tokensAvailable,tokensCapacity:t.tokensCapacity,tokensPausedUntil:t.tokensPausedUntil,blocked:t.blocked,blockedLabel:Q(t.blocked),tokensLabel:n===0?"":`${E(t.tokensAvailable)} / ${E(n)}`,tokensColor:n===0?"":F((1-t.tokensAvailable/n)*300)}}function pe(t){if(!t)return"";const n=t.split(/[\\/]/).filter(Boolean);return n[n.length-1]??""}function me(t){return t.replace(/^ses_/,"").slice(0,8)}function ge(t,n,i){const r=n===1?"1 session":`${n} sessions`,s=t.queued>0?` · ${t.queued} waiting${i===""?"":` on ${i}`}`:"",o=t.tokensCapacity>0?` · ${E(t.tokensAvailable)} new-context tokens`:"";return`${t.active} of ${t.max} slots in use by ${r}${s}${o}`}function Q(t){const n=[];return t.slots>0&&n.push(`slots ${t.slots}`),t.context>0&&n.push(`context ${t.context}`),t.budget>0&&n.push(`budget ${t.budget}`),t.breaker>0&&n.push(`breaker ${t.breaker}`),t.draining>0&&n.push(`draining ${t.draining}`),n.join(" · ")}function he(t){if(!t)return;const n=t.capacity<t.max?`${t.capacity} of ${t.max}`:String(t.max),i=t.calling??0;return{live:t.live,calling:i,queued:t.queued,max:t.max,capacity:t.capacity,label:`${t.live}/${n} live · ${i} calling${t.queued>0?` · ${t.queued} waiting`:""}`}}function E(t){const n=Number.isFinite(t)?Math.max(0,t):0;return n>=1e6?`${(n/1e6).toFixed(1).replace(/\.0$/,"")}m`:n>=1e3?`${Math.round(n/1e3)}k`:String(Math.round(n))}function fe(t){return t.providers.map(n=>de(n))}const ye=20;function be(t,n=ye){const i=new Map((t.sessionDetails??[]).map(r=>[r.sessionID,r]));return t.transitions.slice(-n).reverse().map(r=>ve(r,i.get(r.sessionID)))}function ve(t,n){const i=pe(n?.directory),r=[n?.agent,i].filter(s=>!!s).join(" · ");return{time:we(t.timestamp),providerID:t.providerID,kind:t.kind,sessionID:t.sessionID,sessionLabel:n?.title?.trim()||me(t.sessionID),sessionMeta:r,active:t.active,queued:t.queued}}function qe(t,n,i={}){const r=t(),s=i.refetchIntervalMs??ue;let o=!1,c=0;const h=async()=>{const f=++c;let p;try{p=await r.status({},xe(i.directory))}catch{!o&&f===c&&n(null);return}!o&&f===c&&n(p)};h();const d=r.events.on("changed",()=>{h()}),g=setInterval(()=>{h()},s);return()=>{o=!0,clearInterval(g),d()}}function xe(t){return t===void 0?void 0:{location:{directory:t}}}function W(t){return`${Math.round(t*100)}%`}function we(t){const n=new Date(t),i=r=>String(r).padStart(2,"0");return`${i(n.getHours())}:${i(n.getMinutes())}:${i(n.getSeconds())}`}var $e=e.template("<div class=request-concurrency-status-header aria-hidden=true><span>Provider</span><span>Active</span><span>Queued</span><span>Tokens</span><span>Util</span><span>Demand"),Ce=e.template("<div class=request-concurrency-feed><div class=request-concurrency-feed-title>Recent activity"),Se=e.template("<div class=request-concurrency-status>"),ke=e.template("<div class=request-concurrency-status-unavailable>Status unavailable"),_e=e.template('<div class=request-concurrency-status-row><span class=request-concurrency-status-provider></span><span class=request-concurrency-status-active><span></span><span class=request-concurrency-status-max></span></span><span class=request-concurrency-status-queued></span><span class=request-concurrency-status-tokens></span><span class=request-concurrency-status-utilization title="Utilization: active / max, capped at 100%"></span><span class=request-concurrency-status-demand title="Demand: (active + queued) / max">'),Ae=e.template("<div class=request-concurrency-subagents><span class=request-concurrency-subagents-label>Subagents</span><span class=request-concurrency-subagents-count>"),Pe=e.template("<span class=request-concurrency-feed-session-meta>"),Me=e.template("<div class=request-concurrency-feed-row><span class=request-concurrency-feed-time></span><span></span><span class=request-concurrency-feed-provider></span><span class=request-concurrency-feed-session><span class=request-concurrency-feed-session-name></span></span><span class=request-concurrency-feed-counts>"),N=e.template("<span class=request-concurrency-field-help>"),Le=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input class=request-concurrency-input type=number>"),Te=e.template('<label class="request-concurrency-field request-concurrency-field-inline"><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input type=checkbox>'),De=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><select class=request-concurrency-input>"),Ie=e.template("<option>"),ze=e.template("<div class=request-concurrency-status-unavailable>"),Fe=e.template("<span class=request-concurrency-config-notice>"),je=e.template("<div class=request-concurrency-config><p class=request-concurrency-config-intro>These settings decide how many requests may run at once and what happens when a provider is slow or stops answering. Save applies the change to the running server immediately. Only adding or removing a provider needs a restart.</p><div class=request-concurrency-config-title>Providers</div><p class=request-concurrency-config-help>How many requests may be sent to each provider at the same time. Anything beyond that waits in a queue rather than failing. Set this to the number of parallel requests your plan allows; a higher number is not served by the provider.</p><div class=request-concurrency-config-title>Token budget</div><p class=request-concurrency-config-help>Some providers cap how much brand-new text you may send in a short burst — text they have not already cached from earlier turns. This allowance refills over time. When it is used up, new requests wait for it to refill instead of being rejected.</p><div class=request-concurrency-config-title>Admission</div><p class=request-concurrency-config-help>These decide how many requests run at once and in what order waiting ones are served. The context cap matters most for big fan-outs: it counts the full prompt of every running request, not just the new text, so many long conversations at once can overload a provider even when the request count is within its limit.</p><div class=request-concurrency-config-title>Circuit breaker</div><p class=request-concurrency-config-help>If a provider accepts a request but never answers, every request would sit until it times out and the queue would keep growing. The breaker notices repeated silent failures and stops sending new requests for a while, so the queue stays small and you see the problem quickly.</p><div class=request-concurrency-config-title>Subagents</div><p class=request-concurrency-config-help>A guard on how many child sessions exist at once, for host load and cost — not a model-request limit. A child waiting for a tool holds a permit but no provider slot, so a ceiling near the provider's concurrency throttles the fan-out below what the provider allows and adds a second queue. Set it well above the provider maximum, or leave it at 0 to turn the guard off. The live and calling counts are reported either way when the guard is on.</p><div class=request-concurrency-config-title>Behaviour</div><div class=request-concurrency-config-actions><button type=button class=request-concurrency-save>"),Ee=e.template("<div class=request-concurrency-config-group><div class=request-concurrency-config-subtitle>"),Ne=e.template("<div class=request-concurrency-config-error>"),Re=e.template("<span class=request-concurrency-bar-items>"),Be=e.template('<button type=button class=request-concurrency-bar title="Open concurrency details"aria-label="Open concurrency details"><span class=request-concurrency-bar-label>Concurrency'),Oe=e.template("<span class=request-concurrency-bar-muted>Status unavailable"),Ue=e.template("<span class=request-concurrency-bar-queue>"),He=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider></span><span class=request-concurrency-bar-slots>"),Qe=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider>subagents</span><span>"),We=e.template("<div class=request-concurrency-dialog><div class=request-concurrency-tabs role=tablist><button type=button role=tab>Queue</button><button type=button role=tab>Config"),Ve=e.template("<div class=request-concurrency-status-unavailable>Settings unavailable");const Ye="Status unavailable",Ge={providers:[],transitions:[]};function R(t){if(t===null)return{unavailable:!0,rows:[],transitions:[]};const n=he(t.subagents);return{unavailable:!1,rows:fe(t),transitions:be(t),...n?{subagents:n}:{}}}function V(t){const n=()=>R(t.snapshot);return(()=>{var i=Se();return e.insert(i,e.createComponent(u.Show,{get when(){return!n().unavailable},get fallback(){return ke()},get children(){return[e.createComponent(u.Show,{get when(){return n().rows.length>0},get children(){return $e()}}),e.createComponent(u.For,{get each(){return n().rows},children:r=>(()=>{var s=_e(),o=s.firstChild,c=o.nextSibling,h=c.firstChild,d=h.nextSibling,g=c.nextSibling,f=g.nextSibling,p=f.nextSibling,y=p.nextSibling;return e.insert(o,()=>r.providerID),e.insert(h,()=>r.active),e.insert(d,()=>` / ${r.max}`),e.insert(g,()=>r.queued),e.insert(f,(()=>{var a=e.memo(()=>r.tokensCapacity>0);return()=>a()?r.tokensLabel:"—"})()),e.insert(p,()=>r.utilization),e.insert(y,()=>r.demand),e.effect(a=>{var l=r.demandColor,v=r.providerID,_=`${r.active} of ${r.max} slots in use by ${r.sessions} ${r.sessions===1?"session":"sessions"}`,A=r.utilizationColor,w=r.demandColor,P=r.blockedLabel===""?`${r.queued} waiting`:`${r.queued} waiting (${r.blockedLabel})`,$=r.tokensColor,M=r.tokensCapacity>0?`${r.tokensAvailable} of ${r.tokensCapacity} new-context tokens available`:"No token budget configured",q=r.utilizationColor,L=r.demandColor;return l!==a.e&&e.setStyleProperty(s,"border-left-color",a.e=l),v!==a.t&&e.setAttribute(o,"title",a.t=v),_!==a.a&&e.setAttribute(c,"title",a.a=_),A!==a.o&&e.setStyleProperty(h,"color",a.o=A),w!==a.i&&e.setStyleProperty(g,"color",a.i=w),P!==a.n&&e.setAttribute(g,"title",a.n=P),$!==a.s&&e.setStyleProperty(f,"color",a.s=$),M!==a.h&&e.setAttribute(f,"title",a.h=M),q!==a.r&&e.setStyleProperty(p,"color",a.r=q),L!==a.d&&e.setStyleProperty(y,"color",a.d=L),a},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0}),s})()}),e.createComponent(u.Show,{get when(){return n().subagents},children:r=>(()=>{var s=Ae(),o=s.firstChild,c=o.nextSibling;return e.insert(c,()=>r().label),e.effect(()=>e.setAttribute(c,"title",`${r().live} child sessions hold a permit (${r().calling} are calling the model, the rest are running a tool); ${r().queued} launches wait for a permit, which is a separate limit from the model-request queue`)),s})()}),e.createComponent(u.Show,{get when(){return n().transitions.length>0},get children(){var r=Ce();return r.firstChild,e.insert(r,e.createComponent(u.For,{get each(){return n().transitions},children:s=>(()=>{var o=Me(),c=o.firstChild,h=c.nextSibling,d=h.nextSibling,g=d.nextSibling,f=g.firstChild,p=g.nextSibling;return e.insert(c,()=>s.time),e.insert(h,()=>s.kind),e.insert(d,()=>s.providerID),e.insert(f,()=>s.sessionLabel),e.insert(g,e.createComponent(u.Show,{get when(){return s.sessionMeta!==""},get children(){var y=Pe();return e.insert(y,()=>` · ${s.sessionMeta}`),y}}),null),e.insert(p,()=>`${s.active} active · ${s.queued} queued`),e.effect(y=>{var a=`request-concurrency-feed-kind is-${s.kind}`,l=s.providerID,v=s.sessionMeta===""?s.sessionID:`${s.sessionID} · ${s.sessionMeta}`;return a!==y.e&&e.className(h,y.e=a),l!==y.t&&e.setAttribute(d,"title",y.t=l),v!==y.a&&e.setAttribute(g,"title",y.a=v),y},{e:void 0,t:void 0,a:void 0}),o})()}),null),r}})]}})),i})()}function Y(t,n,i){if(n.length===0)return i;const[r,...s]=n,o={...t},c=o[r];return o[r]=s.length===0?i:Y(c,s,i),o}function b(t){return(()=>{var n=Le(),i=n.firstChild,r=i.firstChild,s=i.nextSibling;return e.insert(r,()=>t.label),e.insert(i,e.createComponent(u.Show,{get when(){return t.help},get children(){var o=N();return e.insert(o,()=>t.help),o}}),null),e.addEventListener(s,"input",o=>{const c=Number(o.currentTarget.value);Number.isFinite(c)&&t.onChange(c)}),e.effect(()=>e.setAttribute(s,"step",t.step??1)),e.effect(()=>s.value=String(t.value)),n})()}function Je(t){return(()=>{var n=Te(),i=n.firstChild,r=i.firstChild,s=i.nextSibling;return e.insert(r,()=>t.label),e.insert(i,e.createComponent(u.Show,{get when(){return t.help},get children(){var o=N();return e.insert(o,()=>t.help),o}}),null),e.addEventListener(s,"change",o=>t.onChange(o.currentTarget.checked)),e.effect(()=>s.checked=t.value),n})()}function Ke(t){return(()=>{var n=De(),i=n.firstChild,r=i.firstChild,s=i.nextSibling;return e.insert(r,()=>t.label),e.insert(i,e.createComponent(u.Show,{get when(){return t.help},get children(){var o=N();return e.insert(o,()=>t.help),o}}),null),e.addEventListener(s,"change",o=>t.onChange(o.currentTarget.value)),e.insert(s,e.createComponent(u.For,{get each(){return t.options},children:o=>(()=>{var c=Ie();return e.insert(c,()=>o.label),e.effect(()=>c.value=o.value),c})()})),e.effect(()=>s.value=t.value),n})()}function G(t){const[n,i]=u.createSignal(null),[r,s]=u.createSignal([]),[o,c]=u.createSignal(""),[h,d]=u.createSignal(!1),[g,f]=u.createSignal(!0);u.createEffect(()=>{let a=!1;Promise.resolve().then(()=>t.client.config({})).then(l=>{a||(i(l),f(!1))}).catch(l=>{a||(s([`Could not read the plugin settings: ${l instanceof Error?l.message:String(l)}`]),f(!1))}),u.onCleanup(()=>{a=!0})});const p=(a,l)=>{const v=n();v&&(i(Y(v,a,l)),c(""))},y=async()=>{const a=n();if(a){d(!0),s([]),c("");try{const l=await t.client.save(a);l.ok?c(l.restartRequired?"Saved. Changing the provider set needs a restart.":"Saved and applied to the running server."):s(l.errors)}catch(l){s([`The save request failed: ${l instanceof Error?l.message:String(l)}`])}finally{d(!1)}}};return[e.createComponent(u.Show,{get when(){return n()},get fallback(){return(()=>{var a=ze();return e.insert(a,()=>g()?"Loading settings…":"Settings unavailable"),a})()},children:a=>(()=>{var l=je(),v=l.firstChild,_=v.nextSibling,A=_.nextSibling,w=A.nextSibling,P=w.nextSibling,$=P.nextSibling,M=$.nextSibling,q=M.nextSibling,L=q.nextSibling,T=L.nextSibling,X=T.nextSibling,B=X.nextSibling,D=B.nextSibling,I=D.firstChild;return e.insert(l,e.createComponent(u.For,{get each(){return Object.keys(a().providers)},children:m=>e.createComponent(b,{label:`${m} · max concurrent`,get value(){return a().providers[m]},onChange:x=>p(["providers",m],x)})}),w),e.insert(l,e.createComponent(u.For,{get each(){return Object.keys(a().tokens)},children:m=>(()=>{var x=Ee(),Z=x.firstChild;return e.insert(Z,m),e.insert(x,e.createComponent(b,{label:"Capacity",help:"Brand-new tokens that may be sent in one burst before requests have to wait. Use the provider's documented burst allowance, for example 500000.",get value(){return a().tokens[m].capacity},onChange:C=>p(["tokens",m,"capacity"],C)}),null),e.insert(x,e.createComponent(b,{label:"Refill per minute",help:"How many brand-new tokens become available again each minute. Use the provider's documented refill rate, for example 500000 per minute.",get value(){return a().tokens[m].refillPerMinute},onChange:C=>p(["tokens",m,"refillPerMinute"],C)}),null),e.insert(x,e.createComponent(b,{label:"Safety factor",step:.05,help:"How much to over-estimate a request before charging it. 1.1 adds a 10% margin, so the allowance is reached slightly early rather than exceeded.",get value(){return a().tokens[m].safetyFactor},onChange:C=>p(["tokens",m,"safetyFactor"],C)}),null),x})()}),$),e.insert(l,e.createComponent(b,{label:"Context in flight (tokens)",help:"The sum of the full prompts of all running requests. A request waits if sending it would push that total over this number. 0 turns the cap off.",get value(){return a().scheduler.contextCapacity},onChange:m=>p(["scheduler","contextCapacity"],m)}),q),e.insert(l,e.createComponent(b,{label:"Context ceiling (tokens)",help:"The largest value the context cap above may grow back to after a stall. The cap shrinks only when the breaker opens, then grows back in quarters on clean completions. 0 keeps the cap fixed at the value above.",get value(){return a().scheduler.contextCeiling},onChange:m=>p(["scheduler","contextCeiling"],m)}),q),e.insert(l,e.createComponent(b,{label:"Reserve share",step:.05,help:"The part of the token budget that small requests may not use, so a large request is not blocked by a stream of small ones. 0.25 keeps 25% free.",get value(){return a().scheduler.reserveShare},onChange:m=>p(["scheduler","reserveShare"],m)}),q),e.insert(l,e.createComponent(b,{label:"Small-request share",step:.05,help:"A request whose cost is at most this fraction of the budget counts as small and must leave the reserve alone. Anything larger may use the reserve.",get value(){return a().scheduler.smallShare},onChange:m=>p(["scheduler","smallShare"],m)}),q),e.insert(l,e.createComponent(b,{label:"Queue aging (ms)",help:"After this many milliseconds a waiting request stops respecting the reserve, so a large request cannot be blocked forever by smaller ones.",get value(){return a().scheduler.agingMs},onChange:m=>p(["scheduler","agingMs"],m)}),q),e.insert(l,e.createComponent(b,{label:"Queue deadline (ms)",help:"How long a request may wait before the plugin gives up and reports a queue timeout. 0 waits as long as needed. Note that the client already abandons a request after 300000 ms, so a larger deadline never fires.",get value(){return a().scheduler.queueDeadlineMs},onChange:m=>p(["scheduler","queueDeadlineMs"],m)}),q),e.insert(l,e.createComponent(b,{label:"Stalls before opening",help:"How many failed attempts in a row, with no response at all, open the breaker. 3 gives the provider three chances.",get value(){return a().scheduler.breaker.threshold},onChange:m=>p(["scheduler","breaker","threshold"],m)}),T),e.insert(l,e.createComponent(b,{label:"Cooldown (ms)",help:"How long the breaker stays open. After this, one test request is allowed: if it succeeds the breaker closes, if it stalls the breaker reopens.",get value(){return a().scheduler.breaker.cooldownMs},onChange:m=>p(["scheduler","breaker","cooldownMs"],m)}),T),e.insert(l,e.createComponent(Ke,{label:"When open",help:"fail fast: new requests are rejected immediately, so you notice the outage now. wait: they stay queued and resume when the cooldown ends.",get value(){return a().scheduler.breaker.mode},options:[{value:"fail",label:"fail fast"},{value:"wait",label:"wait for cooldown"}],onChange:m=>p(["scheduler","breaker","mode"],m)}),T),e.insert(l,e.createComponent(b,{label:"Live child sessions",help:"A runaway guard, not a concurrency limit. A child running a tool counts here but not against the provider. 0 turns the guard off.",get value(){return a().subagents.max},onChange:m=>p(["subagents","max"],m)}),B),e.insert(l,e.createComponent(Je,{label:"Adaptive request width",help:"When on, the number of concurrent requests is halved after a capacity failure (a concurrency 429, a transport failure, or a 5xx) and raised by one after four successful requests in a row. A burst-protection 429 pauses the token bucket instead. When off, the provider maximum above is always used.",get value(){return a().adaptive},onChange:m=>p(["adaptive"],m)}),D),e.addEventListener(I,"click",y),e.insert(I,()=>h()?"Saving…":"Save"),e.insert(D,e.createComponent(u.Show,{get when(){return o()},get children(){var m=Fe();return e.insert(m,o),m}}),null),e.effect(()=>I.disabled=h()),l})()}),e.createComponent(u.For,{get each(){return r()},children:a=>(()=>{var l=Ne();return e.insert(l,a),l})()})]}function J(t){const n=()=>R(t.snapshot);return e.createComponent(u.Show,{get when(){return n().unavailable||n().rows.length>0},get children(){var i=Be();return i.firstChild,e.addEventListener(i,"click",()=>t.onOpen()),e.insert(i,e.createComponent(u.Show,{get when(){return!n().unavailable},get fallback(){return Oe()},get children(){var r=Re();return e.insert(r,e.createComponent(u.For,{get each(){return n().rows},children:s=>(()=>{var o=He(),c=o.firstChild,h=c.nextSibling;return e.insert(c,()=>s.providerID),e.insert(h,()=>s.slotLabel),e.insert(o,e.createComponent(u.Show,{get when(){return s.queued>0},get children(){var d=Ue();return e.insert(d,()=>s.queueLabel),e.effect(g=>{var f=s.demandColor,p=s.title;return f!==g.e&&e.setStyleProperty(d,"color",g.e=f),p!==g.t&&e.setAttribute(d,"title",g.t=p),g},{e:void 0,t:void 0}),d}}),null),e.effect(d=>{var g=s.utilizationColor,f=s.title;return g!==d.e&&e.setStyleProperty(h,"color",d.e=g),f!==d.t&&e.setAttribute(h,"title",d.t=f),d},{e:void 0,t:void 0}),o})()}),null),e.insert(r,e.createComponent(u.Show,{get when(){return n().subagents},children:s=>(()=>{var o=Qe(),c=o.firstChild,h=c.nextSibling;return e.insert(h,()=>s().label),e.effect(()=>e.setAttribute(o,"title",`${s().live} child sessions hold a permit (${s().calling} calling the model); ${s().queued} launches wait for a permit`)),o})()}),null),r}}),null),i}})}function Xe(t){const n=k.usePlugin(),[i,r]=u.createSignal("queue");return e.createComponent(n.ui.Dialog,{title:"Concurrency",size:"x-large",get children(){var s=We(),o=s.firstChild,c=o.firstChild,h=c.nextSibling;return e.addEventListener(c,"click",()=>r("queue")),e.addEventListener(h,"click",()=>r("config")),e.insert(s,e.createComponent(u.Show,{get when(){return i()==="queue"},get children(){return e.createComponent(V,{get snapshot(){return t.snapshot()}})}}),null),e.insert(s,e.createComponent(u.Show,{get when(){return i()==="config"},get children(){return e.createComponent(u.Show,{get when(){return t.client},get fallback(){return Ve()},children:d=>e.createComponent(G,{get client(){return d()}})})}}),null),e.effect(d=>{var g=i()==="queue",f=`request-concurrency-tab${i()==="queue"?" is-active":""}`,p=i()==="config",y=`request-concurrency-tab${i()==="config"?" is-active":""}`;return g!==d.e&&e.setAttribute(c,"aria-selected",d.e=g),f!==d.t&&e.className(c,d.t=f),p!==d.a&&e.setAttribute(h,"aria-selected",d.a=p),y!==d.o&&e.className(h,d.o=y),d},{e:void 0,t:void 0,a:void 0,o:void 0}),s}})}function K(){const t=k.usePlugin(),[n,i]=u.createSignal(Ge),[r,s]=u.createSignal(!1),[o,c]=u.createSignal(null);u.createEffect(()=>{const d=t.servers.list().map(p=>t.servers.get(p)),g=d.find(p=>p?.builtin)??d.find(Boolean);if(!g)return;c(g.client.rpc(U));const f=qe(()=>g.client.rpc(U),p=>{i(p),s(!0)});u.onCleanup(f)});const h=()=>{t.dialogs.open(()=>e.createComponent(Xe,{snapshot:n,get client(){return o()}}))};return e.createComponent(u.Show,{get when(){return r()},get children(){return e.createComponent(J,{get snapshot(){return n()},onOpen:h})}})}const Ze=k.Plugin.define({setup(t){t.add(k.Slot,{at:"window.bottom",render:()=>e.createComponent(K,{})}),t.add(k.Style,ee+te)}});exports.ConfigForm=G;exports.STATUS_UNAVAILABLE=Ye;exports.StatusBar=K;exports.StatusBarBody=J;exports.StatusBody=V;exports.default=Ze;exports.statusBodyState=R;
