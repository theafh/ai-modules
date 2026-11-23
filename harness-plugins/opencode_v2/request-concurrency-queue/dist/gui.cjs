"use strict";Object.defineProperties(exports,{__esModule:{value:!0},[Symbol.toStringTag]:{value:"Module"}});const e=require("solid-js/web"),d=require("solid-js"),k=require("@opencode/plugin/gui"),ee=`
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
`,ne={type:"object",properties:{slots:{type:"integer",minimum:0},context:{type:"integer",minimum:0},budget:{type:"integer",minimum:0},breaker:{type:"integer",minimum:0},draining:{type:"integer",minimum:0}},required:["slots","context","budget","breaker","draining"],additionalProperties:!1},re={type:"object",properties:{providerID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},ceiling:{type:"integer",minimum:0},sessions:{type:"integer",minimum:0},utilization:{type:"number",minimum:0,maximum:1},demand:{type:"number",minimum:0},tokensAvailable:{type:"integer",minimum:0},tokensCapacity:{type:"integer",minimum:0},tokensPausedUntil:{type:"integer",minimum:0},blocked:ne,contextInFlight:{type:"integer",minimum:0},contextCapacity:{type:"integer",minimum:0},breaker:{type:"string",enum:["closed","open","half-open"]},breakerRetryAfterMs:{type:"integer",minimum:0},stalls:{type:"integer",minimum:0}},required:["providerID","active","queued","max","ceiling","utilization","demand","tokensAvailable","tokensCapacity","tokensPausedUntil","blocked","breaker","breakerRetryAfterMs","stalls"],additionalProperties:!1},ae={type:"object",properties:{timestamp:{type:"integer",minimum:0},providerID:{type:"string"},kind:{type:"string",enum:["acquired","queued","released","dequeued"]},sessionID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0}},required:["timestamp","providerID","kind","sessionID","active","queued"],additionalProperties:!1},ie={type:"object",properties:{live:{type:"integer",minimum:0},calling:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},capacity:{type:"integer",minimum:0}},required:["live","calling","queued","max","capacity"],additionalProperties:!1},se={type:"object",properties:{capacity:{type:"integer",minimum:1},refillPerMinute:{type:"integer",minimum:1},safetyFactor:{type:"number",minimum:.1,maximum:10}},required:["capacity","refillPerMinute","safetyFactor"],additionalProperties:!1},oe={type:"object",properties:{contextCapacity:{type:"integer",minimum:0},contextCeiling:{type:"integer",minimum:0},reserveShare:{type:"number",minimum:0,maximum:1},smallShare:{type:"number",minimum:0,maximum:1},agingMs:{type:"integer",minimum:0},queueDeadlineMs:{type:"integer",minimum:0},breaker:{type:"object",properties:{threshold:{type:"integer",minimum:1},cooldownMs:{type:"integer",minimum:0},mode:{type:"string",enum:["fail","wait"]}},required:["threshold","cooldownMs","mode"],additionalProperties:!1}},required:["contextCapacity","contextCeiling","reserveShare","smallShare","agingMs","queueDeadlineMs","breaker"],additionalProperties:!1},O={type:"object",properties:{providers:{type:"object",additionalProperties:{type:"integer",minimum:1}},tokens:{type:"object",additionalProperties:se},scheduler:oe,subagents:{type:"object",properties:{max:{type:"integer",minimum:0},hostAware:{type:"boolean"}},required:["max","hostAware"],additionalProperties:!1},adaptive:{type:"boolean"}},required:["providers","tokens","scheduler","subagents","adaptive"],additionalProperties:!1},ce={type:"object",properties:{ok:{type:"boolean"},errors:{type:"array",items:{type:"string"}},restartRequired:{type:"boolean"}},required:["ok","errors","restartRequired"],additionalProperties:!1},I={type:"object",properties:{},additionalProperties:!1},U={id:"request-concurrency-queue",methods:{status:{input:I,output:{type:"object",properties:{providers:{type:"array",items:re},transitions:{type:"array",items:ae},subagents:ie},required:["providers","transitions"],additionalProperties:!1}},config:{input:I,output:O},save:{input:O,output:ce}},events:{changed:{schema:I}}},S=[{percent:0,hue:145,saturation:60,lightness:28},{percent:100,hue:120,saturation:60,lightness:60},{percent:150,hue:60,saturation:85,lightness:70},{percent:200,hue:32,saturation:95,lightness:55},{percent:250,hue:12,saturation:90,lightness:68},{percent:300,hue:0,saturation:70,lightness:35},{percent:350,hue:-24,saturation:75,lightness:42},{percent:400,hue:-40,saturation:70,lightness:30}];function E(t){const n=Number.isFinite(t)?Math.max(0,t):0,o=S[S.length-1];if(n>=o.percent)return H(o);for(let r=1;r<S.length;r+=1){const a=S[r-1],s=S[r];if(n>s.percent)continue;const c=(n-a.percent)/(s.percent-a.percent);return`hsl(${Math.round(j(a.hue,s.hue,c))} ${Math.round(j(a.saturation,s.saturation,c))}% ${Math.round(j(a.lightness,s.lightness,c))}%)`}return H(o)}function H(t){return`hsl(${t.hue} ${t.saturation}% ${t.lightness}%)`}function j(t,n,o){return t+(n-t)*o}const le=5e3;function ue(t){const n=t.tokensCapacity,o=Q(t.blocked),r=t.sessions??0;return{providerID:t.providerID,active:t.active,queued:t.queued,max:t.max,ceiling:t.ceiling,sessions:r,total:t.active+t.queued,slotLabel:`${t.active}/${t.max}`,queueLabel:t.queued>0?`+${t.queued}`:"",title:de(t,r,o),utilization:W(t.utilization),demand:W(t.demand),utilizationColor:E(t.utilization*100),demandColor:E(t.demand*100),tokensAvailable:t.tokensAvailable,tokensCapacity:t.tokensCapacity,tokensPausedUntil:t.tokensPausedUntil,blocked:t.blocked,blockedLabel:Q(t.blocked),tokensLabel:n===0?"":`${D(t.tokensAvailable)} / ${D(n)}`,tokensColor:n===0?"":E(t.tokensAvailable/n*100)}}function de(t,n,o){const r=n===1?"1 session":`${n} sessions`,a=t.queued>0?` · ${t.queued} waiting${o===""?"":` on ${o}`}`:"",s=t.tokensCapacity>0?` · ${D(t.tokensAvailable)} new-context tokens`:"";return`${t.active} of ${t.max} slots in use by ${r}${a}${s}`}function Q(t){const n=[];return t.slots>0&&n.push(`slots ${t.slots}`),t.context>0&&n.push(`context ${t.context}`),t.budget>0&&n.push(`budget ${t.budget}`),t.breaker>0&&n.push(`breaker ${t.breaker}`),t.draining>0&&n.push(`draining ${t.draining}`),n.join(" · ")}function pe(t){if(!t)return;const n=t.capacity<t.max?`${t.capacity} of ${t.max}`:String(t.max),o=t.calling??0;return{live:t.live,calling:o,queued:t.queued,max:t.max,capacity:t.capacity,label:`${t.live}/${n} live · ${o} calling${t.queued>0?` · ${t.queued} waiting`:""}`}}function D(t){const n=Number.isFinite(t)?Math.max(0,t):0;return n>=1e6?`${(n/1e6).toFixed(1).replace(/\.0$/,"")}m`:n>=1e3?`${Math.round(n/1e3)}k`:String(Math.round(n))}function me(t){return t.providers.map(ue)}const ge=20;function he(t,n=ge){return t.transitions.slice(-n).reverse().map(fe)}function fe(t){return{time:ve(t.timestamp),providerID:t.providerID,kind:t.kind,sessionID:t.sessionID,active:t.active,queued:t.queued}}function ye(t,n,o={}){const r=t(),a=o.refetchIntervalMs??le;let s=!1,c=0;const h=async()=>{const f=++c;let l;try{l=await r.status({},be(o.directory))}catch{!s&&f===c&&n(null);return}!s&&f===c&&n(l)};h();const p=r.events.on("changed",()=>{h()}),g=setInterval(()=>{h()},a);return()=>{s=!0,clearInterval(g),p()}}function be(t){return t===void 0?void 0:{location:{directory:t}}}function W(t){return`${Math.round(t*100)}%`}function ve(t){const n=new Date(t),o=r=>String(r).padStart(2,"0");return`${o(n.getHours())}:${o(n.getMinutes())}:${o(n.getSeconds())}`}var qe=e.template("<div class=request-concurrency-status-header aria-hidden=true><span>Provider</span><span>Active</span><span>Queued</span><span>Tokens</span><span>Util</span><span>Demand"),xe=e.template("<div class=request-concurrency-feed><div class=request-concurrency-feed-title>Recent activity"),we=e.template("<div class=request-concurrency-status>"),Ce=e.template("<div class=request-concurrency-status-unavailable>Status unavailable"),$e=e.template('<div class=request-concurrency-status-row><span class=request-concurrency-status-provider></span><span class=request-concurrency-status-active><span></span><span class=request-concurrency-status-max></span></span><span class=request-concurrency-status-queued></span><span class=request-concurrency-status-tokens></span><span class=request-concurrency-status-utilization title="Utilization: active / max"></span><span class=request-concurrency-status-demand title="Demand: (active + queued) / max">'),Se=e.template("<div class=request-concurrency-subagents><span class=request-concurrency-subagents-label>Subagents</span><span class=request-concurrency-subagents-count>"),ke=e.template("<div class=request-concurrency-feed-row><span class=request-concurrency-feed-time></span><span></span><span class=request-concurrency-feed-provider></span><span class=request-concurrency-feed-session></span><span class=request-concurrency-feed-counts>"),N=e.template("<span class=request-concurrency-field-help>"),_e=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input class=request-concurrency-input type=number>"),Ae=e.template('<label class="request-concurrency-field request-concurrency-field-inline"><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input type=checkbox>'),Pe=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><select class=request-concurrency-input>"),Me=e.template("<option>"),Le=e.template("<div class=request-concurrency-status-unavailable>"),Te=e.template("<span class=request-concurrency-config-notice>"),ze=e.template("<div class=request-concurrency-config><p class=request-concurrency-config-intro>These settings decide how many requests may run at once and what happens when a provider is slow or stops answering. Save applies the change to the running server immediately. Only adding or removing a provider needs a restart.</p><div class=request-concurrency-config-title>Providers</div><p class=request-concurrency-config-help>How many requests may be sent to each provider at the same time. Anything beyond that waits in a queue rather than failing. Set this to the number of parallel requests your plan allows; a higher number is not served by the provider.</p><div class=request-concurrency-config-title>Token budget</div><p class=request-concurrency-config-help>Some providers cap how much brand-new text you may send in a short burst — text they have not already cached from earlier turns. This allowance refills over time. When it is used up, new requests wait for it to refill instead of being rejected.</p><div class=request-concurrency-config-title>Admission</div><p class=request-concurrency-config-help>These decide how many requests run at once and in what order waiting ones are served. The context cap matters most for big fan-outs: it counts the full prompt of every running request, not just the new text, so many long conversations at once can overload a provider even when the request count is within its limit.</p><div class=request-concurrency-config-title>Circuit breaker</div><p class=request-concurrency-config-help>If a provider accepts a request but never answers, every request would sit until it times out and the queue would keep growing. The breaker notices repeated silent failures and stops sending new requests for a while, so the queue stays small and you see the problem quickly.</p><div class=request-concurrency-config-title>Subagents</div><p class=request-concurrency-config-help>A guard on how many child sessions exist at once, for host load and cost — not a model-request limit. A child waiting for a tool holds a permit but no provider slot, so a ceiling near the provider's concurrency throttles the fan-out below what the provider allows and adds a second queue. Set it well above the provider maximum, or leave it at 0 to turn the guard off. The live and calling counts are reported either way when the guard is on.</p><div class=request-concurrency-config-title>Behaviour</div><div class=request-concurrency-config-actions><button type=button class=request-concurrency-save>"),Fe=e.template("<div class=request-concurrency-config-group><div class=request-concurrency-config-subtitle>"),Ie=e.template("<div class=request-concurrency-config-error>"),Ee=e.template("<span class=request-concurrency-bar-items>"),je=e.template('<button type=button class=request-concurrency-bar title="Open concurrency details"aria-label="Open concurrency details"><span class=request-concurrency-bar-label>Concurrency'),De=e.template("<span class=request-concurrency-bar-muted>Status unavailable"),Ne=e.template("<span class=request-concurrency-bar-queue>"),Re=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider></span><span class=request-concurrency-bar-slots>"),Be=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider>subagents</span><span>"),Oe=e.template("<div class=request-concurrency-dialog><div class=request-concurrency-tabs role=tablist><button type=button role=tab>Queue</button><button type=button role=tab>Config"),Ue=e.template("<div class=request-concurrency-status-unavailable>Settings unavailable");const He="Status unavailable",Qe={providers:[],transitions:[]};function R(t){if(t===null)return{unavailable:!0,rows:[],transitions:[]};const n=pe(t.subagents);return{unavailable:!1,rows:me(t),transitions:he(t),...n?{subagents:n}:{}}}function V(t){const n=()=>R(t.snapshot);return(()=>{var o=we();return e.insert(o,e.createComponent(d.Show,{get when(){return!n().unavailable},get fallback(){return Ce()},get children(){return[e.createComponent(d.Show,{get when(){return n().rows.length>0},get children(){return qe()}}),e.createComponent(d.For,{get each(){return n().rows},children:r=>(()=>{var a=$e(),s=a.firstChild,c=s.nextSibling,h=c.firstChild,p=h.nextSibling,g=c.nextSibling,f=g.nextSibling,l=f.nextSibling,b=l.nextSibling;return e.insert(s,()=>r.providerID),e.insert(h,()=>r.active),e.insert(p,()=>` / ${r.max}`),e.insert(g,()=>r.queued),e.insert(f,(()=>{var i=e.memo(()=>r.tokensCapacity>0);return()=>i()?r.tokensLabel:"—"})()),e.insert(l,()=>r.utilization),e.insert(b,()=>r.demand),e.effect(i=>{var u=r.demandColor,q=r.providerID,_=`${r.active} of ${r.max} slots in use by ${r.sessions} ${r.sessions===1?"session":"sessions"}`,A=r.utilizationColor,w=r.demandColor,P=r.blockedLabel===""?`${r.queued} waiting`:`${r.queued} waiting (${r.blockedLabel})`,C=r.tokensColor,M=r.tokensCapacity>0?`${r.tokensAvailable} of ${r.tokensCapacity} new-context tokens available`:"No token budget configured",v=r.utilizationColor,L=r.demandColor;return u!==i.e&&e.setStyleProperty(a,"border-left-color",i.e=u),q!==i.t&&e.setAttribute(s,"title",i.t=q),_!==i.a&&e.setAttribute(c,"title",i.a=_),A!==i.o&&e.setStyleProperty(h,"color",i.o=A),w!==i.i&&e.setStyleProperty(g,"color",i.i=w),P!==i.n&&e.setAttribute(g,"title",i.n=P),C!==i.s&&e.setStyleProperty(f,"color",i.s=C),M!==i.h&&e.setAttribute(f,"title",i.h=M),v!==i.r&&e.setStyleProperty(l,"color",i.r=v),L!==i.d&&e.setStyleProperty(b,"color",i.d=L),i},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0}),a})()}),e.createComponent(d.Show,{get when(){return n().subagents},children:r=>(()=>{var a=Se(),s=a.firstChild,c=s.nextSibling;return e.insert(c,()=>r().label),e.effect(()=>e.setAttribute(c,"title",`${r().live} child sessions hold a permit (${r().calling} are calling the model, the rest are running a tool); ${r().queued} launches wait for a permit, which is a separate limit from the model-request queue`)),a})()}),e.createComponent(d.Show,{get when(){return n().transitions.length>0},get children(){var r=xe();return r.firstChild,e.insert(r,e.createComponent(d.For,{get each(){return n().transitions},children:a=>(()=>{var s=ke(),c=s.firstChild,h=c.nextSibling,p=h.nextSibling,g=p.nextSibling,f=g.nextSibling;return e.insert(c,()=>a.time),e.insert(h,()=>a.kind),e.insert(p,()=>a.providerID),e.insert(g,()=>a.sessionID),e.insert(f,()=>`${a.active} active · ${a.queued} queued`),e.effect(l=>{var b=`request-concurrency-feed-kind is-${a.kind}`,i=a.providerID,u=a.sessionID;return b!==l.e&&e.className(h,l.e=b),i!==l.t&&e.setAttribute(p,"title",l.t=i),u!==l.a&&e.setAttribute(g,"title",l.a=u),l},{e:void 0,t:void 0,a:void 0}),s})()}),null),r}})]}})),o})()}function Y(t,n,o){if(n.length===0)return o;const[r,...a]=n,s={...t},c=s[r];return s[r]=a.length===0?o:Y(c,a,o),s}function y(t){return(()=>{var n=_e(),o=n.firstChild,r=o.firstChild,a=o.nextSibling;return e.insert(r,()=>t.label),e.insert(o,e.createComponent(d.Show,{get when(){return t.help},get children(){var s=N();return e.insert(s,()=>t.help),s}}),null),e.addEventListener(a,"input",s=>{const c=Number(s.currentTarget.value);Number.isFinite(c)&&t.onChange(c)}),e.effect(()=>e.setAttribute(a,"step",t.step??1)),e.effect(()=>a.value=String(t.value)),n})()}function We(t){return(()=>{var n=Ae(),o=n.firstChild,r=o.firstChild,a=o.nextSibling;return e.insert(r,()=>t.label),e.insert(o,e.createComponent(d.Show,{get when(){return t.help},get children(){var s=N();return e.insert(s,()=>t.help),s}}),null),e.addEventListener(a,"change",s=>t.onChange(s.currentTarget.checked)),e.effect(()=>a.checked=t.value),n})()}function Ve(t){return(()=>{var n=Pe(),o=n.firstChild,r=o.firstChild,a=o.nextSibling;return e.insert(r,()=>t.label),e.insert(o,e.createComponent(d.Show,{get when(){return t.help},get children(){var s=N();return e.insert(s,()=>t.help),s}}),null),e.addEventListener(a,"change",s=>t.onChange(s.currentTarget.value)),e.insert(a,e.createComponent(d.For,{get each(){return t.options},children:s=>(()=>{var c=Me();return e.insert(c,()=>s.label),e.effect(()=>c.value=s.value),c})()})),e.effect(()=>a.value=t.value),n})()}function G(t){const[n,o]=d.createSignal(null),[r,a]=d.createSignal([]),[s,c]=d.createSignal(""),[h,p]=d.createSignal(!1),[g,f]=d.createSignal(!0);d.createEffect(()=>{let i=!1;Promise.resolve().then(()=>t.client.config({})).then(u=>{i||(o(u),f(!1))}).catch(u=>{i||(a([`Could not read the plugin settings: ${u instanceof Error?u.message:String(u)}`]),f(!1))}),d.onCleanup(()=>{i=!0})});const l=(i,u)=>{const q=n();q&&(o(Y(q,i,u)),c(""))},b=async()=>{const i=n();if(i){p(!0),a([]),c("");try{const u=await t.client.save(i);u.ok?c(u.restartRequired?"Saved. Changing the provider set needs a restart.":"Saved and applied to the running server."):a(u.errors)}catch(u){a([`The save request failed: ${u instanceof Error?u.message:String(u)}`])}finally{p(!1)}}};return[e.createComponent(d.Show,{get when(){return n()},get fallback(){return(()=>{var i=Le();return e.insert(i,()=>g()?"Loading settings…":"Settings unavailable"),i})()},children:i=>(()=>{var u=ze(),q=u.firstChild,_=q.nextSibling,A=_.nextSibling,w=A.nextSibling,P=w.nextSibling,C=P.nextSibling,M=C.nextSibling,v=M.nextSibling,L=v.nextSibling,T=L.nextSibling,X=T.nextSibling,B=X.nextSibling,z=B.nextSibling,F=z.firstChild;return e.insert(u,e.createComponent(d.For,{get each(){return Object.keys(i().providers)},children:m=>e.createComponent(y,{label:`${m} · max concurrent`,get value(){return i().providers[m]},onChange:x=>l(["providers",m],x)})}),w),e.insert(u,e.createComponent(d.For,{get each(){return Object.keys(i().tokens)},children:m=>(()=>{var x=Fe(),Z=x.firstChild;return e.insert(Z,m),e.insert(x,e.createComponent(y,{label:"Capacity",help:"Brand-new tokens that may be sent in one burst before requests have to wait. Use the provider's documented burst allowance, for example 500000.",get value(){return i().tokens[m].capacity},onChange:$=>l(["tokens",m,"capacity"],$)}),null),e.insert(x,e.createComponent(y,{label:"Refill per minute",help:"How many brand-new tokens become available again each minute. Use the provider's documented refill rate, for example 500000 per minute.",get value(){return i().tokens[m].refillPerMinute},onChange:$=>l(["tokens",m,"refillPerMinute"],$)}),null),e.insert(x,e.createComponent(y,{label:"Safety factor",step:.05,help:"How much to over-estimate a request before charging it. 1.1 adds a 10% margin, so the allowance is reached slightly early rather than exceeded.",get value(){return i().tokens[m].safetyFactor},onChange:$=>l(["tokens",m,"safetyFactor"],$)}),null),x})()}),C),e.insert(u,e.createComponent(y,{label:"Context in flight (tokens)",help:"The sum of the full prompts of all running requests. A request waits if sending it would push that total over this number. 0 turns the cap off.",get value(){return i().scheduler.contextCapacity},onChange:m=>l(["scheduler","contextCapacity"],m)}),v),e.insert(u,e.createComponent(y,{label:"Context ceiling (tokens)",help:"The largest value the context cap above may grow back to after a stall. The cap shrinks only when the breaker opens, then grows back in quarters on clean completions. 0 keeps the cap fixed at the value above.",get value(){return i().scheduler.contextCeiling},onChange:m=>l(["scheduler","contextCeiling"],m)}),v),e.insert(u,e.createComponent(y,{label:"Reserve share",step:.05,help:"The part of the token budget that small requests may not use, so a large request is not blocked by a stream of small ones. 0.25 keeps 25% free.",get value(){return i().scheduler.reserveShare},onChange:m=>l(["scheduler","reserveShare"],m)}),v),e.insert(u,e.createComponent(y,{label:"Small-request share",step:.05,help:"A request whose cost is at most this fraction of the budget counts as small and must leave the reserve alone. Anything larger may use the reserve.",get value(){return i().scheduler.smallShare},onChange:m=>l(["scheduler","smallShare"],m)}),v),e.insert(u,e.createComponent(y,{label:"Queue aging (ms)",help:"After this many milliseconds a waiting request stops respecting the reserve, so a large request cannot be blocked forever by smaller ones.",get value(){return i().scheduler.agingMs},onChange:m=>l(["scheduler","agingMs"],m)}),v),e.insert(u,e.createComponent(y,{label:"Queue deadline (ms)",help:"How long a request may wait before the plugin gives up and reports a queue timeout. 0 waits as long as needed. Note that the client already abandons a request after 300000 ms, so a larger deadline never fires.",get value(){return i().scheduler.queueDeadlineMs},onChange:m=>l(["scheduler","queueDeadlineMs"],m)}),v),e.insert(u,e.createComponent(y,{label:"Stalls before opening",help:"How many failed attempts in a row, with no response at all, open the breaker. 3 gives the provider three chances.",get value(){return i().scheduler.breaker.threshold},onChange:m=>l(["scheduler","breaker","threshold"],m)}),T),e.insert(u,e.createComponent(y,{label:"Cooldown (ms)",help:"How long the breaker stays open. After this, one test request is allowed: if it succeeds the breaker closes, if it stalls the breaker reopens.",get value(){return i().scheduler.breaker.cooldownMs},onChange:m=>l(["scheduler","breaker","cooldownMs"],m)}),T),e.insert(u,e.createComponent(Ve,{label:"When open",help:"fail fast: new requests are rejected immediately, so you notice the outage now. wait: they stay queued and resume when the cooldown ends.",get value(){return i().scheduler.breaker.mode},options:[{value:"fail",label:"fail fast"},{value:"wait",label:"wait for cooldown"}],onChange:m=>l(["scheduler","breaker","mode"],m)}),T),e.insert(u,e.createComponent(y,{label:"Live child sessions",help:"A runaway guard, not a concurrency limit. A child running a tool counts here but not against the provider. 0 turns the guard off.",get value(){return i().subagents.max},onChange:m=>l(["subagents","max"],m)}),B),e.insert(u,e.createComponent(We,{label:"Adaptive request width",help:"When on, the number of concurrent requests is halved after a capacity failure (a concurrency 429, a transport failure, or a 5xx) and raised by one after four successful requests in a row. A burst-protection 429 pauses the token bucket instead. When off, the provider maximum above is always used.",get value(){return i().adaptive},onChange:m=>l(["adaptive"],m)}),z),e.addEventListener(F,"click",b),e.insert(F,()=>h()?"Saving…":"Save"),e.insert(z,e.createComponent(d.Show,{get when(){return s()},get children(){var m=Te();return e.insert(m,s),m}}),null),e.effect(()=>F.disabled=h()),u})()}),e.createComponent(d.For,{get each(){return r()},children:i=>(()=>{var u=Ie();return e.insert(u,i),u})()})]}function J(t){const n=()=>R(t.snapshot);return e.createComponent(d.Show,{get when(){return n().unavailable||n().rows.length>0},get children(){var o=je();return o.firstChild,e.addEventListener(o,"click",()=>t.onOpen()),e.insert(o,e.createComponent(d.Show,{get when(){return!n().unavailable},get fallback(){return De()},get children(){var r=Ee();return e.insert(r,e.createComponent(d.For,{get each(){return n().rows},children:a=>(()=>{var s=Re(),c=s.firstChild,h=c.nextSibling;return e.insert(c,()=>a.providerID),e.insert(h,()=>a.slotLabel),e.insert(s,e.createComponent(d.Show,{get when(){return a.queued>0},get children(){var p=Ne();return e.insert(p,()=>a.queueLabel),e.effect(g=>{var f=a.demandColor,l=a.title;return f!==g.e&&e.setStyleProperty(p,"color",g.e=f),l!==g.t&&e.setAttribute(p,"title",g.t=l),g},{e:void 0,t:void 0}),p}}),null),e.effect(p=>{var g=a.utilizationColor,f=a.title;return g!==p.e&&e.setStyleProperty(h,"color",p.e=g),f!==p.t&&e.setAttribute(h,"title",p.t=f),p},{e:void 0,t:void 0}),s})()}),null),e.insert(r,e.createComponent(d.Show,{get when(){return n().subagents},children:a=>(()=>{var s=Be(),c=s.firstChild,h=c.nextSibling;return e.insert(h,()=>a().label),e.effect(()=>e.setAttribute(s,"title",`${a().live} child sessions hold a permit (${a().calling} calling the model); ${a().queued} launches wait for a permit`)),s})()}),null),r}}),null),o}})}function Ye(t){const n=k.usePlugin(),[o,r]=d.createSignal("queue");return e.createComponent(n.ui.Dialog,{title:"Concurrency",size:"x-large",get children(){var a=Oe(),s=a.firstChild,c=s.firstChild,h=c.nextSibling;return e.addEventListener(c,"click",()=>r("queue")),e.addEventListener(h,"click",()=>r("config")),e.insert(a,e.createComponent(d.Show,{get when(){return o()==="queue"},get children(){return e.createComponent(V,{get snapshot(){return t.snapshot()}})}}),null),e.insert(a,e.createComponent(d.Show,{get when(){return o()==="config"},get children(){return e.createComponent(d.Show,{get when(){return t.client},get fallback(){return Ue()},children:p=>e.createComponent(G,{get client(){return p()}})})}}),null),e.effect(p=>{var g=o()==="queue",f=`request-concurrency-tab${o()==="queue"?" is-active":""}`,l=o()==="config",b=`request-concurrency-tab${o()==="config"?" is-active":""}`;return g!==p.e&&e.setAttribute(c,"aria-selected",p.e=g),f!==p.t&&e.className(c,p.t=f),l!==p.a&&e.setAttribute(h,"aria-selected",p.a=l),b!==p.o&&e.className(h,p.o=b),p},{e:void 0,t:void 0,a:void 0,o:void 0}),a}})}function K(){const t=k.usePlugin(),[n,o]=d.createSignal(Qe),[r,a]=d.createSignal(!1),[s,c]=d.createSignal(null);d.createEffect(()=>{const p=t.servers.list().map(l=>t.servers.get(l)),g=p.find(l=>l?.builtin)??p.find(Boolean);if(!g)return;c(g.client.rpc(U));const f=ye(()=>g.client.rpc(U),l=>{o(l),a(!0)});d.onCleanup(f)});const h=()=>{t.dialogs.open(()=>e.createComponent(Ye,{snapshot:n,get client(){return s()}}))};return e.createComponent(d.Show,{get when(){return r()},get children(){return e.createComponent(J,{get snapshot(){return n()},onOpen:h})}})}const Ge=k.Plugin.define({setup(t){t.add(k.Slot,{at:"window.bottom",render:()=>e.createComponent(K,{})}),t.add(k.Style,ee+te)}});exports.ConfigForm=G;exports.STATUS_UNAVAILABLE=He;exports.StatusBar=K;exports.StatusBarBody=J;exports.StatusBody=V;exports.default=Ge;exports.statusBodyState=R;
