"use strict";Object.defineProperties(exports,{__esModule:{value:!0},[Symbol.toStringTag]:{value:"Module"}});const e=require("solid-js/web"),p=require("solid-js"),$=require("@opencode/plugin/gui"),Z=`
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

.request-concurrency-bar-muted {
  font-style: italic;
  opacity: 0.6;
}

.request-concurrency-dialog .request-concurrency-status {
  padding: 0;
}
`,ee=`
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
`,te={type:"object",properties:{providerID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},ceiling:{type:"integer",minimum:0},utilization:{type:"number",minimum:0,maximum:1},demand:{type:"number",minimum:0},tokensAvailable:{type:"integer",minimum:0},tokensCapacity:{type:"integer",minimum:0},tokensPausedUntil:{type:"integer",minimum:0},contextInFlight:{type:"integer",minimum:0},contextCapacity:{type:"integer",minimum:0},breaker:{type:"string",enum:["closed","open","half-open"]},breakerRetryAfterMs:{type:"integer",minimum:0},stalls:{type:"integer",minimum:0}},required:["providerID","active","queued","max","ceiling","utilization","demand","tokensAvailable","tokensCapacity","tokensPausedUntil","breaker","breakerRetryAfterMs","stalls"],additionalProperties:!1},ne={type:"object",properties:{timestamp:{type:"integer",minimum:0},providerID:{type:"string"},kind:{type:"string",enum:["acquired","queued","released","dequeued"]},sessionID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0}},required:["timestamp","providerID","kind","sessionID","active","queued"],additionalProperties:!1},re={type:"object",properties:{live:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},capacity:{type:"integer",minimum:0}},required:["live","queued","max","capacity"],additionalProperties:!1},ie={type:"object",properties:{capacity:{type:"integer",minimum:1},refillPerMinute:{type:"integer",minimum:1},safetyFactor:{type:"number",minimum:.1,maximum:10}},required:["capacity","refillPerMinute","safetyFactor"],additionalProperties:!1},ae={type:"object",properties:{contextCapacity:{type:"integer",minimum:0},contextCeiling:{type:"integer",minimum:0},reserveShare:{type:"number",minimum:0,maximum:1},smallShare:{type:"number",minimum:0,maximum:1},agingMs:{type:"integer",minimum:0},queueDeadlineMs:{type:"integer",minimum:0},breaker:{type:"object",properties:{threshold:{type:"integer",minimum:1},cooldownMs:{type:"integer",minimum:0},mode:{type:"string",enum:["fail","wait"]}},required:["threshold","cooldownMs","mode"],additionalProperties:!1}},required:["contextCapacity","contextCeiling","reserveShare","smallShare","agingMs","queueDeadlineMs","breaker"],additionalProperties:!1},B={type:"object",properties:{providers:{type:"object",additionalProperties:{type:"integer",minimum:1}},tokens:{type:"object",additionalProperties:ie},scheduler:ae,subagents:{type:"object",properties:{max:{type:"integer",minimum:0},hostAware:{type:"boolean"}},required:["max","hostAware"],additionalProperties:!1},adaptive:{type:"boolean"}},required:["providers","tokens","scheduler","subagents","adaptive"],additionalProperties:!1},se={type:"object",properties:{ok:{type:"boolean"},errors:{type:"array",items:{type:"string"}},restartRequired:{type:"boolean"}},required:["ok","errors","restartRequired"],additionalProperties:!1},I={type:"object",properties:{},additionalProperties:!1},O={id:"request-concurrency-queue",methods:{status:{input:I,output:{type:"object",properties:{providers:{type:"array",items:te},transitions:{type:"array",items:ne},subagents:re},required:["providers","transitions"],additionalProperties:!1}},config:{input:I,output:B},save:{input:B,output:se}},events:{changed:{schema:I}}},k=[{percent:0,hue:145,saturation:60,lightness:28},{percent:100,hue:120,saturation:60,lightness:60},{percent:150,hue:60,saturation:85,lightness:70},{percent:200,hue:32,saturation:95,lightness:55},{percent:250,hue:12,saturation:90,lightness:68},{percent:300,hue:0,saturation:70,lightness:35},{percent:350,hue:-24,saturation:75,lightness:42},{percent:400,hue:-40,saturation:70,lightness:30}];function E(t){const r=Number.isFinite(t)?Math.max(0,t):0,s=k[k.length-1];if(r>=s.percent)return U(s);for(let a=1;a<k.length;a+=1){const i=k[a-1],o=k[a];if(r>o.percent)continue;const u=(r-i.percent)/(o.percent-i.percent);return`hsl(${Math.round(D(i.hue,o.hue,u))} ${Math.round(D(i.saturation,o.saturation,u))}% ${Math.round(D(i.lightness,o.lightness,u))}%)`}return U(s)}function U(t){return`hsl(${t.hue} ${t.saturation}% ${t.lightness}%)`}function D(t,r,s){return t+(r-t)*s}const oe=5e3;function ce(t){const r=t.tokensCapacity;return{providerID:t.providerID,active:t.active,queued:t.queued,max:t.max,ceiling:t.ceiling,total:t.active+t.queued,utilization:Q(t.utilization),demand:Q(t.demand),utilizationColor:E(t.utilization*100),demandColor:E(t.demand*100),tokensAvailable:t.tokensAvailable,tokensCapacity:t.tokensCapacity,tokensPausedUntil:t.tokensPausedUntil,tokensLabel:r===0?"":`${H(t.tokensAvailable)} / ${H(r)}`,tokensColor:r===0?"":E(t.tokensAvailable/r*100)}}function H(t){const r=Number.isFinite(t)?Math.max(0,t):0;return r>=1e6?`${(r/1e6).toFixed(1).replace(/\.0$/,"")}m`:r>=1e3?`${Math.round(r/1e3)}k`:String(Math.round(r))}function le(t){return t.providers.map(ce)}const ue=20;function de(t,r=ue){return t.transitions.slice(-r).reverse().map(pe)}function pe(t){return{time:he(t.timestamp),providerID:t.providerID,kind:t.kind,sessionID:t.sessionID,active:t.active,queued:t.queued}}function me(t,r,s={}){const a=t(),i=s.refetchIntervalMs??oe;let o=!1,u=0;const g=async()=>{const f=++u;let l;try{l=await a.status({},ge(s.directory))}catch{!o&&f===u&&r(null);return}!o&&f===u&&r(l)};g();const m=a.events.on("changed",()=>{g()}),h=setInterval(()=>{g()},i);return()=>{o=!0,clearInterval(h),m()}}function ge(t){return t===void 0?void 0:{location:{directory:t}}}function Q(t){return`${Math.round(t*100)}%`}function he(t){const r=new Date(t),s=a=>String(a).padStart(2,"0");return`${s(r.getHours())}:${s(r.getMinutes())}:${s(r.getSeconds())}`}var fe=e.template("<div class=request-concurrency-status-header aria-hidden=true><span>Provider</span><span>Active</span><span>Queued</span><span>Tokens</span><span>Util</span><span>Demand"),ye=e.template("<div class=request-concurrency-feed><div class=request-concurrency-feed-title>Recent activity"),be=e.template("<div class=request-concurrency-status>"),ve=e.template("<div class=request-concurrency-status-unavailable>Status unavailable"),qe=e.template('<div class=request-concurrency-status-row><span class=request-concurrency-status-provider></span><span class=request-concurrency-status-active><span></span><span class=request-concurrency-status-max></span></span><span class=request-concurrency-status-queued></span><span class=request-concurrency-status-tokens></span><span class=request-concurrency-status-utilization title="Utilization: active / max"></span><span class=request-concurrency-status-demand title="Demand: (active + queued) / max">'),xe=e.template("<div class=request-concurrency-feed-row><span class=request-concurrency-feed-time></span><span></span><span class=request-concurrency-feed-provider></span><span class=request-concurrency-feed-session></span><span class=request-concurrency-feed-counts>"),N=e.template("<span class=request-concurrency-field-help>"),Ce=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input class=request-concurrency-input type=number>"),Se=e.template('<label class="request-concurrency-field request-concurrency-field-inline"><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><input type=checkbox>'),we=e.template("<label class=request-concurrency-field><span class=request-concurrency-field-text><span class=request-concurrency-field-label></span></span><select class=request-concurrency-input>"),ke=e.template("<option>"),$e=e.template("<div class=request-concurrency-status-unavailable>"),_e=e.template("<span class=request-concurrency-config-notice>"),Ae=e.template("<div class=request-concurrency-config><p class=request-concurrency-config-intro>These settings decide how many requests may run at once and what happens when a provider is slow or stops answering. Save applies the change to the running server immediately. Only adding or removing a provider needs a restart.</p><div class=request-concurrency-config-title>Providers</div><p class=request-concurrency-config-help>How many requests may be sent to each provider at the same time. Anything beyond that waits in a queue rather than failing. Set this to the number of parallel requests your plan allows; a higher number is not served by the provider.</p><div class=request-concurrency-config-title>Token budget</div><p class=request-concurrency-config-help>Some providers cap how much brand-new text you may send in a short burst — text they have not already cached from earlier turns. This allowance refills over time. When it is used up, new requests wait for it to refill instead of being rejected.</p><div class=request-concurrency-config-title>Admission</div><p class=request-concurrency-config-help>These decide how many requests run at once and in what order waiting ones are served. The context cap matters most for big fan-outs: it counts the full prompt of every running request, not just the new text, so many long conversations at once can overload a provider even when the request count is within its limit.</p><div class=request-concurrency-config-title>Circuit breaker</div><p class=request-concurrency-config-help>If a provider accepts a request but never answers, every request would sit until it times out and the queue would keep growing. The breaker notices repeated silent failures and stops sending new requests for a while, so the queue stays small and you see the problem quickly.</p><div class=request-concurrency-config-title>Subagents</div><p class=request-concurrency-config-help>Separate from model requests: this limits how many child sessions (subagents) may be running at the same time. A child that is waiting for a tool still counts, so this is the number of subagents alive at once, not the number calling the model.</p><div class=request-concurrency-config-title>Behaviour</div><div class=request-concurrency-config-actions><button type=button class=request-concurrency-save>"),Pe=e.template("<div class=request-concurrency-config-group><div class=request-concurrency-config-subtitle>"),Me=e.template("<div class=request-concurrency-config-error>"),Te=e.template("<span class=request-concurrency-bar-items>"),ze=e.template('<button type=button class=request-concurrency-bar title="Open concurrency details"aria-label="Open concurrency details"><span class=request-concurrency-bar-label>Concurrency'),Fe=e.template("<span class=request-concurrency-bar-muted>Status unavailable"),Le=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider></span><span>"),Ie=e.template("<div class=request-concurrency-dialog><div class=request-concurrency-tabs role=tablist><button type=button role=tab>Queue</button><button type=button role=tab>Config"),Ee=e.template("<div class=request-concurrency-status-unavailable>Settings unavailable");const De="Status unavailable",Ne={providers:[],transitions:[]};function j(t){return t===null?{unavailable:!0,rows:[],transitions:[]}:{unavailable:!1,rows:le(t),transitions:de(t)}}function W(t){const r=()=>j(t.snapshot);return(()=>{var s=be();return e.insert(s,e.createComponent(p.Show,{get when(){return!r().unavailable},get fallback(){return ve()},get children(){return[e.createComponent(p.Show,{get when(){return r().rows.length>0},get children(){return fe()}}),e.createComponent(p.For,{get each(){return r().rows},children:a=>(()=>{var i=qe(),o=i.firstChild,u=o.nextSibling,g=u.firstChild,m=g.nextSibling,h=u.nextSibling,f=h.nextSibling,l=f.nextSibling,b=l.nextSibling;return e.insert(o,()=>a.providerID),e.insert(g,()=>a.active),e.insert(m,()=>` / ${a.max}`),e.insert(h,()=>a.queued),e.insert(f,(()=>{var n=e.memo(()=>a.tokensCapacity>0);return()=>n()?a.tokensLabel:"—"})()),e.insert(l,()=>a.utilization),e.insert(b,()=>a.demand),e.effect(n=>{var c=a.demandColor,q=a.providerID,_=`${a.active} of ${a.max} slots in use`,A=a.utilizationColor,C=a.demandColor,P=`${a.queued} waiting`,S=a.tokensColor,M=a.tokensCapacity>0?`${a.tokensAvailable} of ${a.tokensCapacity} new-context tokens available`:"No token budget configured",v=a.utilizationColor,T=a.demandColor;return c!==n.e&&e.setStyleProperty(i,"border-left-color",n.e=c),q!==n.t&&e.setAttribute(o,"title",n.t=q),_!==n.a&&e.setAttribute(u,"title",n.a=_),A!==n.o&&e.setStyleProperty(g,"color",n.o=A),C!==n.i&&e.setStyleProperty(h,"color",n.i=C),P!==n.n&&e.setAttribute(h,"title",n.n=P),S!==n.s&&e.setStyleProperty(f,"color",n.s=S),M!==n.h&&e.setAttribute(f,"title",n.h=M),v!==n.r&&e.setStyleProperty(l,"color",n.r=v),T!==n.d&&e.setStyleProperty(b,"color",n.d=T),n},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0,r:void 0,d:void 0}),i})()}),e.createComponent(p.Show,{get when(){return r().transitions.length>0},get children(){var a=ye();return a.firstChild,e.insert(a,e.createComponent(p.For,{get each(){return r().transitions},children:i=>(()=>{var o=xe(),u=o.firstChild,g=u.nextSibling,m=g.nextSibling,h=m.nextSibling,f=h.nextSibling;return e.insert(u,()=>i.time),e.insert(g,()=>i.kind),e.insert(m,()=>i.providerID),e.insert(h,()=>i.sessionID),e.insert(f,()=>`${i.active} active · ${i.queued} queued`),e.effect(l=>{var b=`request-concurrency-feed-kind is-${i.kind}`,n=i.providerID,c=i.sessionID;return b!==l.e&&e.className(g,l.e=b),n!==l.t&&e.setAttribute(m,"title",l.t=n),c!==l.a&&e.setAttribute(h,"title",l.a=c),l},{e:void 0,t:void 0,a:void 0}),o})()}),null),a}})]}})),s})()}function V(t,r,s){if(r.length===0)return s;const[a,...i]=r,o={...t},u=o[a];return o[a]=i.length===0?s:V(u,i,s),o}function y(t){return(()=>{var r=Ce(),s=r.firstChild,a=s.firstChild,i=s.nextSibling;return e.insert(a,()=>t.label),e.insert(s,e.createComponent(p.Show,{get when(){return t.help},get children(){var o=N();return e.insert(o,()=>t.help),o}}),null),e.addEventListener(i,"input",o=>{const u=Number(o.currentTarget.value);Number.isFinite(u)&&t.onChange(u)}),e.effect(()=>e.setAttribute(i,"step",t.step??1)),e.effect(()=>i.value=String(t.value)),r})()}function je(t){return(()=>{var r=Se(),s=r.firstChild,a=s.firstChild,i=s.nextSibling;return e.insert(a,()=>t.label),e.insert(s,e.createComponent(p.Show,{get when(){return t.help},get children(){var o=N();return e.insert(o,()=>t.help),o}}),null),e.addEventListener(i,"change",o=>t.onChange(o.currentTarget.checked)),e.effect(()=>i.checked=t.value),r})()}function Re(t){return(()=>{var r=we(),s=r.firstChild,a=s.firstChild,i=s.nextSibling;return e.insert(a,()=>t.label),e.insert(s,e.createComponent(p.Show,{get when(){return t.help},get children(){var o=N();return e.insert(o,()=>t.help),o}}),null),e.addEventListener(i,"change",o=>t.onChange(o.currentTarget.value)),e.insert(i,e.createComponent(p.For,{get each(){return t.options},children:o=>(()=>{var u=ke();return e.insert(u,()=>o.label),e.effect(()=>u.value=o.value),u})()})),e.effect(()=>i.value=t.value),r})()}function Y(t){const[r,s]=p.createSignal(null),[a,i]=p.createSignal([]),[o,u]=p.createSignal(""),[g,m]=p.createSignal(!1),[h,f]=p.createSignal(!0);p.createEffect(()=>{let n=!1;Promise.resolve().then(()=>t.client.config({})).then(c=>{n||(s(c),f(!1))}).catch(c=>{n||(i([`Could not read the plugin settings: ${c instanceof Error?c.message:String(c)}`]),f(!1))}),p.onCleanup(()=>{n=!0})});const l=(n,c)=>{const q=r();q&&(s(V(q,n,c)),u(""))},b=async()=>{const n=r();if(n){m(!0),i([]),u("");try{const c=await t.client.save(n);c.ok?u(c.restartRequired?"Saved. Changing the provider set needs a restart.":"Saved and applied to the running server."):i(c.errors)}catch(c){i([`The save request failed: ${c instanceof Error?c.message:String(c)}`])}finally{m(!1)}}};return[e.createComponent(p.Show,{get when(){return r()},get fallback(){return(()=>{var n=$e();return e.insert(n,()=>h()?"Loading settings…":"Settings unavailable"),n})()},children:n=>(()=>{var c=Ae(),q=c.firstChild,_=q.nextSibling,A=_.nextSibling,C=A.nextSibling,P=C.nextSibling,S=P.nextSibling,M=S.nextSibling,v=M.nextSibling,T=v.nextSibling,z=T.nextSibling,K=z.nextSibling,R=K.nextSibling,F=R.nextSibling,L=F.firstChild;return e.insert(c,e.createComponent(p.For,{get each(){return Object.keys(n().providers)},children:d=>e.createComponent(y,{label:`${d} · max concurrent`,get value(){return n().providers[d]},onChange:x=>l(["providers",d],x)})}),C),e.insert(c,e.createComponent(p.For,{get each(){return Object.keys(n().tokens)},children:d=>(()=>{var x=Pe(),X=x.firstChild;return e.insert(X,d),e.insert(x,e.createComponent(y,{label:"Capacity",help:"Brand-new tokens that may be sent in one burst before requests have to wait. Seibert allows 400000.",get value(){return n().tokens[d].capacity},onChange:w=>l(["tokens",d,"capacity"],w)}),null),e.insert(x,e.createComponent(y,{label:"Refill per minute",help:"How many brand-new tokens become available again each minute. Seibert refills 400000 per minute.",get value(){return n().tokens[d].refillPerMinute},onChange:w=>l(["tokens",d,"refillPerMinute"],w)}),null),e.insert(x,e.createComponent(y,{label:"Safety factor",step:.05,help:"How much to over-estimate a request before charging it. 1.1 adds a 10% margin, so the allowance is reached slightly early rather than exceeded.",get value(){return n().tokens[d].safetyFactor},onChange:w=>l(["tokens",d,"safetyFactor"],w)}),null),x})()}),S),e.insert(c,e.createComponent(y,{label:"Context in flight (tokens)",help:"The sum of the full prompts of all running requests. A request waits if sending it would push that total over this number. 0 turns the cap off.",get value(){return n().scheduler.contextCapacity},onChange:d=>l(["scheduler","contextCapacity"],d)}),v),e.insert(c,e.createComponent(y,{label:"Context ceiling (tokens)",help:"After a provider stall the cap above is halved. This is the largest value it may grow back to. 0 keeps the cap fixed at the value above.",get value(){return n().scheduler.contextCeiling},onChange:d=>l(["scheduler","contextCeiling"],d)}),v),e.insert(c,e.createComponent(y,{label:"Reserve share",step:.05,help:"The part of the token budget that small requests may not use, so a large request is not blocked by a stream of small ones. 0.25 keeps 25% free.",get value(){return n().scheduler.reserveShare},onChange:d=>l(["scheduler","reserveShare"],d)}),v),e.insert(c,e.createComponent(y,{label:"Small-request share",step:.05,help:"A request whose cost is at most this fraction of the budget counts as small and must leave the reserve alone. Anything larger may use the reserve.",get value(){return n().scheduler.smallShare},onChange:d=>l(["scheduler","smallShare"],d)}),v),e.insert(c,e.createComponent(y,{label:"Queue aging (ms)",help:"After this many milliseconds a waiting request stops respecting the reserve, so a large request cannot be blocked forever by smaller ones.",get value(){return n().scheduler.agingMs},onChange:d=>l(["scheduler","agingMs"],d)}),v),e.insert(c,e.createComponent(y,{label:"Queue deadline (ms)",help:"How long a request may wait before the plugin gives up and reports a queue timeout. 0 waits as long as needed. Note that the client already abandons a request after 300000 ms, so a larger deadline never fires.",get value(){return n().scheduler.queueDeadlineMs},onChange:d=>l(["scheduler","queueDeadlineMs"],d)}),v),e.insert(c,e.createComponent(y,{label:"Stalls before opening",help:"How many failed attempts in a row, with no response at all, open the breaker. 2 gives the provider two chances.",get value(){return n().scheduler.breaker.threshold},onChange:d=>l(["scheduler","breaker","threshold"],d)}),z),e.insert(c,e.createComponent(y,{label:"Cooldown (ms)",help:"How long the breaker stays open. After this, one test request is allowed: if it succeeds the breaker closes, if it stalls the breaker reopens.",get value(){return n().scheduler.breaker.cooldownMs},onChange:d=>l(["scheduler","breaker","cooldownMs"],d)}),z),e.insert(c,e.createComponent(Re,{label:"When open",help:"fail fast: new requests are rejected immediately, so you notice the outage now. wait: they stay queued and resume when the cooldown ends.",get value(){return n().scheduler.breaker.mode},options:[{value:"fail",label:"fail fast"},{value:"wait",label:"wait for cooldown"}],onChange:d=>l(["scheduler","breaker","mode"],d)}),z),e.insert(c,e.createComponent(y,{label:"Live child sessions",help:"Maximum subagents running at once. 0 turns this limit off.",get value(){return n().subagents.max},onChange:d=>l(["subagents","max"],d)}),R),e.insert(c,e.createComponent(je,{label:"Adaptive request width",help:"When on, the number of concurrent requests is halved after a failure and raised by one after four successful requests in a row. When off, the provider maximum above is always used.",get value(){return n().adaptive},onChange:d=>l(["adaptive"],d)}),F),e.addEventListener(L,"click",b),e.insert(L,()=>g()?"Saving…":"Save"),e.insert(F,e.createComponent(p.Show,{get when(){return o()},get children(){var d=_e();return e.insert(d,o),d}}),null),e.effect(()=>L.disabled=g()),c})()}),e.createComponent(p.For,{get each(){return a()},children:n=>(()=>{var c=Me();return e.insert(c,n),c})()})]}function G(t){const r=()=>j(t.snapshot);return e.createComponent(p.Show,{get when(){return r().unavailable||r().rows.length>0},get children(){var s=ze();return s.firstChild,e.addEventListener(s,"click",()=>t.onOpen()),e.insert(s,e.createComponent(p.Show,{get when(){return!r().unavailable},get fallback(){return Fe()},get children(){var a=Te();return e.insert(a,e.createComponent(p.For,{get each(){return r().rows},children:i=>(()=>{var o=Le(),u=o.firstChild,g=u.nextSibling;return e.insert(u,()=>i.providerID),e.insert(g,()=>`${i.total}/${i.max}`),e.effect(m=>{var h=i.demandColor,f=`${i.total} of ${i.max} slots in demand${i.tokensCapacity>0?` · ${i.tokensAvailable} new-context tokens`:""}`;return h!==m.e&&e.setStyleProperty(g,"color",m.e=h),f!==m.t&&e.setAttribute(g,"title",m.t=f),m},{e:void 0,t:void 0}),o})()})),a}}),null),s}})}function Be(t){const r=$.usePlugin(),[s,a]=p.createSignal("queue");return e.createComponent(r.ui.Dialog,{title:"Concurrency",size:"x-large",get children(){var i=Ie(),o=i.firstChild,u=o.firstChild,g=u.nextSibling;return e.addEventListener(u,"click",()=>a("queue")),e.addEventListener(g,"click",()=>a("config")),e.insert(i,e.createComponent(p.Show,{get when(){return s()==="queue"},get children(){return e.createComponent(W,{get snapshot(){return t.snapshot()}})}}),null),e.insert(i,e.createComponent(p.Show,{get when(){return s()==="config"},get children(){return e.createComponent(p.Show,{get when(){return t.client},get fallback(){return Ee()},children:m=>e.createComponent(Y,{get client(){return m()}})})}}),null),e.effect(m=>{var h=s()==="queue",f=`request-concurrency-tab${s()==="queue"?" is-active":""}`,l=s()==="config",b=`request-concurrency-tab${s()==="config"?" is-active":""}`;return h!==m.e&&e.setAttribute(u,"aria-selected",m.e=h),f!==m.t&&e.className(u,m.t=f),l!==m.a&&e.setAttribute(g,"aria-selected",m.a=l),b!==m.o&&e.className(g,m.o=b),m},{e:void 0,t:void 0,a:void 0,o:void 0}),i}})}function J(){const t=$.usePlugin(),[r,s]=p.createSignal(Ne),[a,i]=p.createSignal(!1),[o,u]=p.createSignal(null);p.createEffect(()=>{const m=t.servers.list().map(l=>t.servers.get(l)),h=m.find(l=>l?.builtin)??m.find(Boolean);if(!h)return;u(h.client.rpc(O));const f=me(()=>h.client.rpc(O),l=>{s(l),i(!0)});p.onCleanup(f)});const g=()=>{t.dialogs.open(()=>e.createComponent(Be,{snapshot:r,get client(){return o()}}))};return e.createComponent(p.Show,{get when(){return a()},get children(){return e.createComponent(G,{get snapshot(){return r()},onOpen:g})}})}const Oe=$.Plugin.define({setup(t){t.add($.Slot,{at:"window.bottom",render:()=>e.createComponent(J,{})}),t.add($.Style,Z+ee)}});exports.ConfigForm=Y;exports.STATUS_UNAVAILABLE=De;exports.StatusBar=J;exports.StatusBarBody=G;exports.StatusBody=W;exports.default=Oe;exports.statusBodyState=j;
