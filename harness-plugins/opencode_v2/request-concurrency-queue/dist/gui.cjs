"use strict";Object.defineProperties(exports,{__esModule:{value:!0},[Symbol.toStringTag]:{value:"Module"}});const e=require("solid-js/web"),u=require("solid-js"),D=require("@opencode/plugin/gui"),ce=`
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
`,le=`
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

.request-concurrency-provider-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: end;
  gap: 6px;
}

.request-concurrency-provider-remove,
.request-concurrency-provider-add-button {
  padding: 4px 10px;
  border: 1px solid rgba(127, 127, 127, 0.4);
  border-radius: 4px;
  background: rgba(127, 127, 127, 0.08);
  color: inherit;
  font: inherit;
  font-size: 11px;
  cursor: pointer;
}

.request-concurrency-provider-remove:hover,
.request-concurrency-provider-add-button:hover {
  background: rgba(127, 127, 127, 0.16);
}

.request-concurrency-provider-add {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 6em auto;
  align-items: center;
  gap: 6px;
  margin-top: 6px;
  padding: 6px 8px;
  border-radius: 4px;
  background: rgba(127, 127, 127, 0.04);
}

.request-concurrency-provider-add-id {
  text-align: left;
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
`,ue={type:"object",properties:{slots:{type:"integer",minimum:0},context:{type:"integer",minimum:0},budget:{type:"integer",minimum:0},breaker:{type:"integer",minimum:0},draining:{type:"integer",minimum:0}},required:["slots","context","budget","breaker","draining"],additionalProperties:!1},de={type:"object",properties:{providerID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},ceiling:{type:"integer",minimum:0},sessions:{type:"integer",minimum:0},activeSessionIDs:{type:"array",items:{type:"string"}},utilization:{type:"number",minimum:0,maximum:1},demand:{type:"number",minimum:0},tokensAvailable:{type:"integer",minimum:0},tokensCapacity:{type:"integer",minimum:0},tokensPausedUntil:{type:"integer",minimum:0},blocked:ue,contextInFlight:{type:"integer",minimum:0},contextCapacity:{type:"integer",minimum:0},breaker:{type:"string",enum:["closed","open","half-open"]},breakerRetryAfterMs:{type:"integer",minimum:0},stalls:{type:"integer",minimum:0}},required:["providerID","active","queued","max","ceiling","utilization","demand","tokensAvailable","tokensCapacity","tokensPausedUntil","blocked","breaker","breakerRetryAfterMs","stalls"],additionalProperties:!1},pe={type:"object",properties:{timestamp:{type:"integer",minimum:0},providerID:{type:"string"},kind:{type:"string",enum:["acquired","queued","released","dequeued"]},sessionID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0}},required:["timestamp","providerID","kind","sessionID","active","queued"],additionalProperties:!1},me={type:"object",properties:{sessionID:{type:"string"},title:{type:"string"},agent:{type:"string"},directory:{type:"string"},parentID:{type:"string"}},required:["sessionID"],additionalProperties:!1},ge={type:"object",properties:{live:{type:"integer",minimum:0},calling:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},capacity:{type:"integer",minimum:0}},required:["live","calling","queued","max","capacity"],additionalProperties:!1},he={type:"object",properties:{capacity:{type:"integer",minimum:1},refillPerMinute:{type:"integer",minimum:1},safetyFactor:{type:"number",minimum:.1,maximum:10}},required:["capacity","refillPerMinute","safetyFactor"],additionalProperties:!1},fe={type:"object",properties:{contextCapacity:{type:"integer",minimum:0},contextCeiling:{type:"integer",minimum:0},reserveShare:{type:"number",minimum:0,maximum:1},smallShare:{type:"number",minimum:0,maximum:1},agingMs:{type:"integer",minimum:0},queueDeadlineMs:{type:"integer",minimum:0},breaker:{type:"object",properties:{threshold:{type:"integer",minimum:1},cooldownMs:{type:"integer",minimum:0},mode:{type:"string",enum:["fail","wait"]}},required:["threshold","cooldownMs","mode"],additionalProperties:!1}},required:["contextCapacity","contextCeiling","reserveShare","smallShare","agingMs","queueDeadlineMs","breaker"],additionalProperties:!1},U={type:"object",properties:{providers:{type:"object",additionalProperties:{type:"integer",minimum:1}},tokens:{type:"object",additionalProperties:he},scheduler:fe,subagents:{type:"object",properties:{max:{type:"integer",minimum:0},hostAware:{type:"boolean"}},required:["max","hostAware"],additionalProperties:!1},adaptive:{type:"boolean"}},required:["providers","tokens","scheduler","subagents","adaptive"],additionalProperties:!1},ye={type:"object",properties:{ok:{type:"boolean"},errors:{type:"array",items:{type:"string"}},restartRequired:{type:"boolean"}},required:["ok","errors","restartRequired"],additionalProperties:!1},z={type:"object",properties:{},additionalProperties:!1},H={id:"request-concurrency-queue",methods:{status:{input:z,output:{type:"object",properties:{providers:{type:"array",items:de},transitions:{type:"array",items:pe},sessionDetails:{type:"array",items:me},subagents:ge},required:["providers","transitions"],additionalProperties:!1}},config:{input:z,output:U},save:{input:U,output:ye}},events:{changed:{schema:z}}},M=[{percent:0,hue:145,saturation:60,lightness:28},{percent:100,hue:120,saturation:60,lightness:60},{percent:150,hue:60,saturation:85,lightness:70},{percent:200,hue:32,saturation:95,lightness:55},{percent:250,hue:12,saturation:90,lightness:68},{percent:300,hue:0,saturation:70,lightness:35},{percent:350,hue:-24,saturation:75,lightness:42},{percent:400,hue:-40,saturation:70,lightness:30}];function N(t){const n=Number.isFinite(t)?Math.max(0,t):0,i=M[M.length-1];if(n>=i.percent)return W(i);for(let r=1;r<M.length;r+=1){const a=M[r-1],s=M[r];if(n>s.percent)continue;const o=(n-a.percent)/(s.percent-a.percent);return`hsl(${Math.round(R(a.hue,s.hue,o))} ${Math.round(R(a.saturation,s.saturation,o))}% ${Math.round(R(a.lightness,s.lightness,o))}%)`}return W(i)}function W(t){return`hsl(${t.hue} ${t.saturation}% ${t.lightness}%)`}function R(t,n,i){return t+(n-t)*i}const be=5e3;function ve(t){const n=t.tokensCapacity,i=Q(t.blocked),r=t.sessions??0;return{providerID:t.providerID,active:t.active,queued:t.queued,max:t.max,ceiling:t.ceiling,sessions:r,total:t.active+t.queued,slotLabel:`${t.active}/${t.max}`,queueLabel:t.queued>0?`+${t.queued}`:"",title:we(t,r,i),utilization:V(t.utilization),demand:V(t.demand),utilizationColor:N(t.active/t.max*100),demandColor:N(t.demand*100),tokensAvailable:t.tokensAvailable,tokensCapacity:t.tokensCapacity,tokensPausedUntil:t.tokensPausedUntil,blocked:t.blocked,blockedLabel:Q(t.blocked),tokensLabel:n===0?"":`${j(t.tokensAvailable)} / ${j(n)}`,tokensColor:n===0?"":N((1-t.tokensAvailable/n)*300)}}function qe(t){if(!t)return"";const n=t.split(/[\\/]/).filter(Boolean);return n[n.length-1]??""}function xe(t){return t.replace(/^ses_/,"").slice(0,8)}function we(t,n,i){const r=n===1?"1 session":`${n} sessions`,a=t.queued>0?` · ${t.queued} waiting${i===""?"":` on ${i}`}`:"",s=t.tokensCapacity>0?` · ${j(t.tokensAvailable)} new-context tokens`:"";return`${t.active} of ${t.max} slots in use by ${r}${a}${s}`}function Q(t){const n=[];return t.slots>0&&n.push(`slots ${t.slots}`),t.context>0&&n.push(`context ${t.context}`),t.budget>0&&n.push(`budget ${t.budget}`),t.breaker>0&&n.push(`breaker ${t.breaker}`),t.draining>0&&n.push(`draining ${t.draining}`),n.join(" · ")}function $e(t){if(!t)return;const n=t.capacity<t.max?`${t.capacity} of ${t.max}`:String(t.max),i=t.calling??0;return{live:t.live,calling:i,queued:t.queued,max:t.max,capacity:t.capacity,label:`${t.live}/${n} live · ${i} calling${t.queued>0?` · ${t.queued} waiting`:""}`}}function j(t){const n=Number.isFinite(t)?Math.max(0,t):0;return n>=1e6?`${(n/1e6).toFixed(1).replace(/\.0$/,"")}m`:n>=1e3?`${Math.round(n/1e3)}k`:String(Math.round(n))}function Ce(t){return t.providers.map(n=>ve(n))}const Se=20;function ke(t,n=Se){const i=new Map((t.sessionDetails??[]).map(r=>[r.sessionID,r]));return t.transitions.slice(-n).reverse().map(r=>_e(r,i.get(r.sessionID)))}function _e(t,n){const i=qe(n?.directory),r=[n?.agent,i].filter(a=>!!a).join(" · ");return{time:Me(t.timestamp),providerID:t.providerID,kind:t.kind,sessionID:t.sessionID,sessionLabel:n?.title?.trim()||xe(t.sessionID),sessionMeta:r,active:t.active,queued:t.queued}}function Ae(t,n,i={}){const r=t(),a=i.refetchIntervalMs??be;let s=!1,o=0;const g=async()=>{const f=++o;let y;try{y=await r.status({},Pe(i.directory))}catch{!s&&f===o&&n(null);return}!s&&f===o&&n(y)};g();const c=r.events.on("changed",()=>{g()}),m=setInterval(()=>{g()},a);return()=>{s=!0,clearInterval(m),c()}}function Pe(t){return t===void 0?void 0:{location:{directory:t}}}function V(t){return`${Math.round(t*100)}%`}function Me(t){const n=new Date(t),i=r=>String(r).padStart(2,"0");return`${i(n.getHours())}:${i(n.getMinutes())}:${i(n.getSeconds())}`}var De=e.template("<div class=request-concurrency-status-header aria-hidden=true><span>Provider</span><span>Active</span><span>Queued</span><span>Tokens</span><span>Util</span><span>Demand"),Le=e.template("<div class=request-concurrency-feed><div class=request-concurrency-feed-title>Recent activity"),Ie=e.template("<div class=request-concurrency-status>"),Te=e.template("<div class=request-concurrency-status-unavailable>Status unavailable"),Ee=e.template('<div class=request-concurrency-status-row><span class=request-concurrency-status-provider></span><span class=request-concurrency-status-active><span></span><span class=request-concurrency-status-max></span></span><span class=request-concurrency-status-queued></span><span class=request-concurrency-status-tokens></span><span class=request-concurrency-status-utilization title="Utilization: active / max, capped at 100%"></span><span class=request-concurrency-status-demand title="Demand: (active + queued) / max">'),ze=e.template("<div class=request-concurrency-subagents><span class=request-concurrency-subagents-label>Subagents</span><span class=request-concurrency-subagents-count>"),Ne=e.template("<span class=request-concurrency-feed-session-meta>"),Re=e.template("<div class=request-concurrency-feed-row><span class=request-concurrency-feed-time></span><span></span><span class=request-concurrency-feed-provider></span><span class=request-concurrency-feed-session><span class=request-concurrency-feed-session-name></span></span><span class=request-concurrency-feed-counts>"),B=e.template("<span class=request-concurrency-field-help>"),je=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input class=request-concurrency-input type=number>"),Fe=e.template('<label class="request-concurrency-field request-concurrency-field-inline"><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input type=checkbox>'),Be=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><select class=request-concurrency-input>"),Oe=e.template("<option>"),Ue=e.template("<div class=request-concurrency-config-title>Subagents"),He=e.template("<p class=request-concurrency-config-help>A guard on how many child sessions exist at once, for host load and cost — not a model-request limit. A child waiting for a tool holds a permit but no provider slot, so a ceiling near the provider's concurrency throttles the fan-out below what the provider allows and adds a second queue. Set it well above the provider maximum, or leave it at 0 to turn the guard off. The live and calling counts are reported either way when the guard is on."),We=e.template("<div class=request-concurrency-config-title>Providers"),Qe=e.template("<p class=request-concurrency-config-help>How many requests may be sent to each provider at the same time. Anything beyond that waits in a queue rather than failing. Set this to the number of parallel requests your plan allows; a higher number is not served by the provider."),Ve=e.template('<div class=request-concurrency-provider-add><input class="request-concurrency-input request-concurrency-provider-add-id"type=text placeholder="provider ID"aria-label="New provider ID"><input class="request-concurrency-input request-concurrency-provider-add-max"type=number min=1 step=1 aria-label="New provider maximum"><button type=button class=request-concurrency-provider-add-button>Add provider'),Y=e.template("<div class=request-concurrency-config-error>"),Ye=e.template("<div class=request-concurrency-provider-row><button type=button class=request-concurrency-provider-remove>Remove"),Ge=e.template("<div class=request-concurrency-status-unavailable>"),Je=e.template("<span class=request-concurrency-config-notice>"),Ke=e.template("<div class=request-concurrency-config><p class=request-concurrency-config-intro>These settings decide how many requests may run at once and what happens when a provider is slow or stops answering. Save applies the change to the running server immediately. Only adding or removing a provider needs a restart.</p><div class=request-concurrency-config-title>Token budget</div><p class=request-concurrency-config-help>Some providers cap how much brand-new text you may send in a short burst — text they have not already cached from earlier turns. This allowance refills over time. When it is used up, new requests wait for it to refill instead of being rejected.</p><div class=request-concurrency-config-title>Admission</div><p class=request-concurrency-config-help>These decide how many requests run at once and in what order waiting ones are served. The context cap matters most for big fan-outs: it counts the full prompt of every running request, not just the new text, so many long conversations at once can overload a provider even when the request count is within its limit.</p><div class=request-concurrency-config-title>Circuit breaker</div><p class=request-concurrency-config-help>If a provider accepts a request but never answers, every request would sit until it times out and the queue would keep growing. The breaker notices repeated silent failures and stops sending new requests for a while, so the queue stays small and you see the problem quickly.</p><div class=request-concurrency-config-title>Behaviour</div><div class=request-concurrency-config-actions><button type=button class=request-concurrency-save>"),Xe=e.template("<div class=request-concurrency-config-group><div class=request-concurrency-config-subtitle>"),Ze=e.template("<span class=request-concurrency-bar-items>"),et=e.template('<button type=button class=request-concurrency-bar title="Open concurrency details"aria-label="Open concurrency details"><span class=request-concurrency-bar-label>Concurrency'),tt=e.template("<span class=request-concurrency-bar-muted>Status unavailable"),nt=e.template("<span class=request-concurrency-bar-queue>"),rt=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider></span><span class=request-concurrency-bar-slots>"),at=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider>subagents</span><span>"),it=e.template("<div class=request-concurrency-dialog><div class=request-concurrency-tabs role=tablist><button type=button role=tab>Queue</button><button type=button role=tab>Config"),st=e.template("<div class=request-concurrency-status-unavailable>Settings unavailable");const ot="Status unavailable",ct={providers:[],transitions:[]};function O(t){if(t===null)return{unavailable:!0,rows:[],transitions:[]};const n=$e(t.subagents);return{unavailable:!1,rows:Ce(t),transitions:ke(t),...n?{subagents:n}:{}}}function G(t){const n=()=>O(t.snapshot);return(()=>{var i=Ie();return e.insert(i,e.createComponent(u.Show,{get when(){return!n().unavailable},get fallback(){return Te()},get children(){return[e.createComponent(u.Show,{get when(){return n().rows.length>0},get children(){return De()}}),e.createComponent(u.For,{get each(){return n().rows},children:r=>(()=>{var a=Ee(),s=a.firstChild,o=s.nextSibling,g=o.firstChild,c=g.nextSibling,m=o.nextSibling,f=m.nextSibling,y=f.nextSibling,v=y.nextSibling;return e.insert(s,()=>r.providerID),e.insert(g,()=>r.active),e.insert(c,()=>` / ${r.max}`),e.insert(m,()=>r.queued),e.insert(f,(()=>{var h=e.memo(()=>r.tokensCapacity>0);return()=>h()?r.tokensLabel:"—"})()),e.insert(y,()=>r.utilization),e.insert(v,()=>r.demand),e.effect(h=>{var $=r.demandColor,b=r.providerID,S=`${r.active} of ${r.max} slots in use by ${r.sessions} ${r.sessions===1?"session":"sessions"}`,L=r.utilizationColor,p=r.demandColor,l=r.blockedLabel===""?`${r.queued} waiting`:`${r.queued} waiting (${r.blockedLabel})`,q=r.tokensColor,k=r.tokensCapacity>0?`${r.tokensAvailable} of ${r.tokensCapacity} new-context tokens available`:"No token budget configured",I=r.utilizationColor,_=r.demandColor;return $!==h.e&&e.setStyleProperty(a,"border-left-color",h.e=$),b!==h.t&&e.setAttribute(s,"title",h.t=b),S!==h.a&&e.setAttribute(o,"title",h.a=S),L!==h.o&&e.setStyleProperty(g,"color",h.o=L),p!==h.i&&e.setStyleProperty(m,"color",h.i=p),l!==h.n&&e.setAttribute(m,"title",h.n=l),q!==h.s&&e.setStyleProperty(f,"color",h.s=q),k!==h.h&&e.setAttribute(f,"title",h.h=k),I!==h.r&&e.setStyleProperty(y,"color",h.r=I),_!==h.d&&e.setStyleProperty(v,"color",h.d=_),h},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0}),a})()}),e.createComponent(u.Show,{get when(){return n().subagents},children:r=>(()=>{var a=ze(),s=a.firstChild,o=s.nextSibling;return e.insert(o,()=>r().label),e.effect(()=>e.setAttribute(o,"title",`${r().live} child sessions hold a permit (${r().calling} are calling the model, the rest are running a tool); ${r().queued} launches wait for a permit, which is a separate limit from the model-request queue`)),a})()}),e.createComponent(u.Show,{get when(){return n().transitions.length>0},get children(){var r=Le();return r.firstChild,e.insert(r,e.createComponent(u.For,{get each(){return n().transitions},children:a=>(()=>{var s=Re(),o=s.firstChild,g=o.nextSibling,c=g.nextSibling,m=c.nextSibling,f=m.firstChild,y=m.nextSibling;return e.insert(o,()=>a.time),e.insert(g,()=>a.kind),e.insert(c,()=>a.providerID),e.insert(f,()=>a.sessionLabel),e.insert(m,e.createComponent(u.Show,{get when(){return a.sessionMeta!==""},get children(){var v=Ne();return e.insert(v,()=>` · ${a.sessionMeta}`),v}}),null),e.insert(y,()=>`${a.active} active · ${a.queued} queued`),e.effect(v=>{var h=`request-concurrency-feed-kind is-${a.kind}`,$=a.providerID,b=a.sessionMeta===""?a.sessionID:`${a.sessionID} · ${a.sessionMeta}`;return h!==v.e&&e.className(g,v.e=h),$!==v.t&&e.setAttribute(c,"title",v.t=$),b!==v.a&&e.setAttribute(m,"title",v.a=b),v},{e:void 0,t:void 0,a:void 0}),s})()}),null),r}})]}})),i})()}function J(t,n,i){if(n.length===0)return i;const[r,...a]=n,s={...t},o=s[r];return s[r]=a.length===0?i:J(o,a,i),s}function x(t){return(()=>{var n=je(),i=n.firstChild,r=i.firstChild,a=i.nextSibling;return e.insert(r,()=>t.label),e.insert(i,e.createComponent(u.Show,{get when(){return t.help},get children(){var s=B();return e.insert(s,()=>t.help),s}}),null),e.addEventListener(a,"input",s=>{const o=Number(s.currentTarget.value);Number.isFinite(o)&&t.onChange(o)}),e.effect(()=>e.setAttribute(a,"step",t.step??1)),e.effect(()=>a.value=String(t.value)),n})()}function K(t){return(()=>{var n=Fe(),i=n.firstChild,r=i.firstChild,a=i.nextSibling;return e.insert(r,()=>t.label),e.insert(i,e.createComponent(u.Show,{get when(){return t.help},get children(){var s=B();return e.insert(s,()=>t.help),s}}),null),e.addEventListener(a,"change",s=>t.onChange(s.currentTarget.checked)),e.effect(()=>a.checked=t.value),n})()}function lt(t){return(()=>{var n=Be(),i=n.firstChild,r=i.firstChild,a=i.nextSibling;return e.insert(r,()=>t.label),e.insert(i,e.createComponent(u.Show,{get when(){return t.help},get children(){var s=B();return e.insert(s,()=>t.help),s}}),null),e.addEventListener(a,"change",s=>t.onChange(s.currentTarget.value)),e.insert(a,e.createComponent(u.For,{get each(){return t.options},children:s=>(()=>{var o=Oe();return e.insert(o,()=>s.label),e.effect(()=>o.value=s.value),o})()})),e.effect(()=>a.value=t.value),n})()}function F(t,n){return{...t,...n}}function X(t){return[Ue(),He(),e.createComponent(x,{label:"Live child sessions",help:"A runaway guard, not a concurrency limit. A child running a tool counts here but not against the provider. 0 turns the guard off.",get value(){return t.max},onChange:n=>t.onChange(F({max:t.max,hostAware:t.hostAware},{max:n}))}),e.createComponent(K,{label:"Host-aware ceiling",help:"When on, the machine's one-minute load average lowers the ceiling above, so a busy machine runs fewer child sessions than the maximum. When off, the maximum always applies.",get value(){return t.hostAware},onChange:n=>t.onChange(F({max:t.max,hostAware:t.hostAware},{hostAware:n}))})]}function Z(t,n){if(n.kind==="add"){const a=n.providerID.trim();if(a==="")throw new Error("A provider ID is required.");if(Object.hasOwn(t.providers,a))throw new Error(`Provider "${a}" is already configured.`);if(!Number.isInteger(n.max)||n.max<1)throw new Error("The maximum must be a positive integer.");return{providers:{...t.providers,[a]:n.max},tokens:{...t.tokens}}}const i={...t.providers},r={...t.tokens};return delete i[n.providerID],delete r[n.providerID],{providers:i,tokens:r}}function ee(t){return t!==null&&t.ok&&t.restartRequired}function te(t){const[n,i]=u.createSignal(""),[r,a]=u.createSignal("1"),s=()=>{t.onAdd(n(),Number(r()))&&(i(""),a("1"))};return[We(),Qe(),e.createComponent(u.For,{get each(){return Object.keys(t.providers)},children:o=>(()=>{var g=Ye(),c=g.firstChild;return e.insert(g,e.createComponent(x,{label:`${o} · max concurrent`,get value(){return t.providers[o]},onChange:m=>t.onMaxChange(o,m)}),c),e.addEventListener(c,"click",()=>t.onRemove(o)),e.setAttribute(c,"aria-label",`Remove ${o}`),e.setAttribute(c,"title",`Remove ${o}`),g})()}),(()=>{var o=Ve(),g=o.firstChild,c=g.nextSibling,m=c.nextSibling;return e.addEventListener(g,"input",f=>i(f.currentTarget.value)),e.addEventListener(c,"input",f=>a(f.currentTarget.value)),e.addEventListener(m,"click",s),e.effect(()=>g.value=n()),e.effect(()=>c.value=r()),o})(),e.createComponent(u.Show,{get when(){return t.error},get children(){var o=Y();return e.insert(o,()=>t.error),o}})]}function ne(t){const[n,i]=u.createSignal(null),[r,a]=u.createSignal([]),[s,o]=u.createSignal(""),[g,c]=u.createSignal(""),[m,f]=u.createSignal(!1),[y,v]=u.createSignal(!0),[h,$]=u.createSignal(null);u.createEffect(()=>{let p=!1;Promise.resolve().then(()=>t.client.config({})).then(l=>{p||(i(l),v(!1))}).catch(l=>{p||(a([`Could not read the plugin settings: ${l instanceof Error?l.message:String(l)}`]),v(!1))}),u.onCleanup(()=>{p=!0})});const b=(p,l)=>{const q=n();q&&(i(J(q,p,l)),o(""))},S=p=>{const l=n();if(!l)return!1;try{const q=Z({providers:l.providers,tokens:l.tokens},p);return i({...l,providers:q.providers,tokens:q.tokens}),c(""),o(""),!0}catch(q){return c(q instanceof Error?q.message:String(q)),!1}},L=async()=>{const p=n();if(p){f(!0),a([]),o("");try{const l=await t.client.save(p);$(l),l.ok?o(l.restartRequired?"Saved. Changing the provider set needs a restart; reopen this dialog to edit the saved set.":"Saved and applied to the running server."):a(l.errors)}catch(l){$(null),a([`The save request failed: ${l instanceof Error?l.message:String(l)}`])}finally{f(!1)}}};return[e.createComponent(u.Show,{get when(){return n()},get fallback(){return(()=>{var p=Ge();return e.insert(p,()=>y()?"Loading settings…":"Settings unavailable"),p})()},children:p=>(()=>{var l=Ke(),q=l.firstChild,k=q.nextSibling,I=k.nextSibling,_=I.nextSibling,ie=_.nextSibling,C=ie.nextSibling,se=C.nextSibling,A=se.nextSibling,T=A.nextSibling,E=T.firstChild;return e.insert(l,e.createComponent(te,{get providers(){return p().providers},onMaxChange:(d,w)=>b(["providers",d],w),onRemove:d=>S({kind:"remove",providerID:d}),onAdd:(d,w)=>S({kind:"add",providerID:d,max:w}),get error(){return g()}}),k),e.insert(l,e.createComponent(u.For,{get each(){return Object.keys(p().tokens)},children:d=>(()=>{var w=Xe(),oe=w.firstChild;return e.insert(oe,d),e.insert(w,e.createComponent(x,{label:"Capacity",help:"Brand-new tokens that may be sent in one burst before requests have to wait. Use the provider's documented burst allowance, for example 500000.",get value(){return p().tokens[d].capacity},onChange:P=>b(["tokens",d,"capacity"],P)}),null),e.insert(w,e.createComponent(x,{label:"Refill per minute",help:"How many brand-new tokens become available again each minute. Use the provider's documented refill rate, for example 500000 per minute.",get value(){return p().tokens[d].refillPerMinute},onChange:P=>b(["tokens",d,"refillPerMinute"],P)}),null),e.insert(w,e.createComponent(x,{label:"Safety factor",step:.05,help:"How much to over-estimate a request before charging it. 1.1 adds a 10% margin, so the allowance is reached slightly early rather than exceeded.",get value(){return p().tokens[d].safetyFactor},onChange:P=>b(["tokens",d,"safetyFactor"],P)}),null),w})()}),_),e.insert(l,e.createComponent(x,{label:"Context in flight (tokens)",help:"The sum of the full prompts of all running requests. A request waits if sending it would push that total over this number. 0 turns the cap off.",get value(){return p().scheduler.contextCapacity},onChange:d=>b(["scheduler","contextCapacity"],d)}),C),e.insert(l,e.createComponent(x,{label:"Context ceiling (tokens)",help:"The largest value the context cap above may grow back to after a stall. The cap shrinks only when the breaker opens, then grows back in quarters on clean completions. 0 keeps the cap fixed at the value above.",get value(){return p().scheduler.contextCeiling},onChange:d=>b(["scheduler","contextCeiling"],d)}),C),e.insert(l,e.createComponent(x,{label:"Reserve share",step:.05,help:"The part of the token budget that small requests may not use, so a large request is not blocked by a stream of small ones. 0.25 keeps 25% free.",get value(){return p().scheduler.reserveShare},onChange:d=>b(["scheduler","reserveShare"],d)}),C),e.insert(l,e.createComponent(x,{label:"Small-request share",step:.05,help:"A request whose cost is at most this fraction of the budget counts as small and must leave the reserve alone. Anything larger may use the reserve.",get value(){return p().scheduler.smallShare},onChange:d=>b(["scheduler","smallShare"],d)}),C),e.insert(l,e.createComponent(x,{label:"Queue aging (ms)",help:"After this many milliseconds a waiting request stops respecting the reserve, so a large request cannot be blocked forever by smaller ones.",get value(){return p().scheduler.agingMs},onChange:d=>b(["scheduler","agingMs"],d)}),C),e.insert(l,e.createComponent(x,{label:"Queue deadline (ms)",help:"How long a request may wait before the plugin gives up and reports a queue timeout. 0 waits as long as needed. Note that the client already abandons a request after 300000 ms, so a larger deadline never fires.",get value(){return p().scheduler.queueDeadlineMs},onChange:d=>b(["scheduler","queueDeadlineMs"],d)}),C),e.insert(l,e.createComponent(x,{label:"Stalls before opening",help:"How many failed attempts in a row, with no response at all, open the breaker. 3 gives the provider three chances.",get value(){return p().scheduler.breaker.threshold},onChange:d=>b(["scheduler","breaker","threshold"],d)}),A),e.insert(l,e.createComponent(x,{label:"Cooldown (ms)",help:"How long the breaker stays open. After this, one test request is allowed: if it succeeds the breaker closes, if it stalls the breaker reopens.",get value(){return p().scheduler.breaker.cooldownMs},onChange:d=>b(["scheduler","breaker","cooldownMs"],d)}),A),e.insert(l,e.createComponent(lt,{label:"When open",help:"fail fast: new requests are rejected immediately, so you notice the outage now. wait: they stay queued and resume when the cooldown ends.",get value(){return p().scheduler.breaker.mode},options:[{value:"fail",label:"fail fast"},{value:"wait",label:"wait for cooldown"}],onChange:d=>b(["scheduler","breaker","mode"],d)}),A),e.insert(l,e.createComponent(X,{get max(){return p().subagents.max},get hostAware(){return p().subagents.hostAware},onChange:d=>{b(["subagents","hostAware"],d.hostAware),b(["subagents","max"],d.max)}}),A),e.insert(l,e.createComponent(K,{label:"Adaptive request width",help:"When on, the number of concurrent requests is halved after a capacity failure (a concurrency 429, a transport failure, or a 5xx) and raised by one after four successful requests in a row. A burst-protection 429 pauses the token bucket instead. When off, the provider maximum above is always used.",get value(){return p().adaptive},onChange:d=>b(["adaptive"],d)}),T),e.addEventListener(E,"click",L),e.insert(E,()=>m()?"Saving…":"Save"),e.insert(T,e.createComponent(u.Show,{get when(){return s()},get children(){var d=Je();return e.insert(d,s),d}}),null),e.effect(()=>E.disabled=m()||ee(h())),l})()}),e.createComponent(u.For,{get each(){return r()},children:p=>(()=>{var l=Y();return e.insert(l,p),l})()})]}function re(t){const n=()=>O(t.snapshot);return e.createComponent(u.Show,{get when(){return n().unavailable||n().rows.length>0},get children(){var i=et();return i.firstChild,e.addEventListener(i,"click",()=>t.onOpen()),e.insert(i,e.createComponent(u.Show,{get when(){return!n().unavailable},get fallback(){return tt()},get children(){var r=Ze();return e.insert(r,e.createComponent(u.For,{get each(){return n().rows},children:a=>(()=>{var s=rt(),o=s.firstChild,g=o.nextSibling;return e.insert(o,()=>a.providerID),e.insert(g,()=>a.slotLabel),e.insert(s,e.createComponent(u.Show,{get when(){return a.queued>0},get children(){var c=nt();return e.insert(c,()=>a.queueLabel),e.effect(m=>{var f=a.demandColor,y=a.title;return f!==m.e&&e.setStyleProperty(c,"color",m.e=f),y!==m.t&&e.setAttribute(c,"title",m.t=y),m},{e:void 0,t:void 0}),c}}),null),e.effect(c=>{var m=a.utilizationColor,f=a.title;return m!==c.e&&e.setStyleProperty(g,"color",c.e=m),f!==c.t&&e.setAttribute(g,"title",c.t=f),c},{e:void 0,t:void 0}),s})()}),null),e.insert(r,e.createComponent(u.Show,{get when(){return n().subagents},children:a=>(()=>{var s=at(),o=s.firstChild,g=o.nextSibling;return e.insert(g,()=>a().label),e.effect(()=>e.setAttribute(s,"title",`${a().live} child sessions hold a permit (${a().calling} calling the model); ${a().queued} launches wait for a permit`)),s})()}),null),r}}),null),i}})}function ut(t){const n=D.usePlugin(),[i,r]=u.createSignal("queue");return e.createComponent(n.ui.Dialog,{title:"Concurrency",size:"x-large",get children(){var a=it(),s=a.firstChild,o=s.firstChild,g=o.nextSibling;return e.addEventListener(o,"click",()=>r("queue")),e.addEventListener(g,"click",()=>r("config")),e.insert(a,e.createComponent(u.Show,{get when(){return i()==="queue"},get children(){return e.createComponent(G,{get snapshot(){return t.snapshot()}})}}),null),e.insert(a,e.createComponent(u.Show,{get when(){return i()==="config"},get children(){return e.createComponent(u.Show,{get when(){return t.client},get fallback(){return st()},children:c=>e.createComponent(ne,{get client(){return c()}})})}}),null),e.effect(c=>{var m=i()==="queue",f=`request-concurrency-tab${i()==="queue"?" is-active":""}`,y=i()==="config",v=`request-concurrency-tab${i()==="config"?" is-active":""}`;return m!==c.e&&e.setAttribute(o,"aria-selected",c.e=m),f!==c.t&&e.className(o,c.t=f),y!==c.a&&e.setAttribute(g,"aria-selected",c.a=y),v!==c.o&&e.className(g,c.o=v),c},{e:void 0,t:void 0,a:void 0,o:void 0}),a}})}function ae(){const t=D.usePlugin(),[n,i]=u.createSignal(ct),[r,a]=u.createSignal(!1),[s,o]=u.createSignal(null);u.createEffect(()=>{const c=t.servers.list().map(y=>t.servers.get(y)),m=c.find(y=>y?.builtin)??c.find(Boolean);if(!m)return;o(m.client.rpc(H));const f=Ae(()=>m.client.rpc(H),y=>{i(y),a(!0)});u.onCleanup(f)});const g=()=>{t.dialogs.open(()=>e.createComponent(ut,{snapshot:n,get client(){return s()}}))};return e.createComponent(u.Show,{get when(){return r()},get children(){return e.createComponent(re,{get snapshot(){return n()},onOpen:g})}})}const dt=D.Plugin.define({setup(t){t.add(D.Slot,{at:"window.bottom",render:()=>e.createComponent(ae,{})}),t.add(D.Style,ce+le)}});exports.ConfigForm=ne;exports.ProvidersSection=te;exports.STATUS_UNAVAILABLE=ot;exports.StatusBar=ae;exports.StatusBarBody=re;exports.StatusBody=G;exports.SubagentsSection=X;exports.default=dt;exports.editedProviders=Z;exports.editedSubagents=F;exports.saveDisabled=ee;exports.statusBodyState=O;
