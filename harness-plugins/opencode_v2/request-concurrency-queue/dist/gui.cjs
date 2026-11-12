"use strict";Object.defineProperties(exports,{__esModule:{value:!0},[Symbol.toStringTag]:{value:"Module"}});const e=require("solid-js/web"),m=require("solid-js"),h=require("@opencode/plugin/gui"),T=`
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
  grid-template-columns: minmax(0, 1fr) 4.5em 4em 3.5em 3.5em;
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
`,B={type:"object",properties:{providerID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},utilization:{type:"number",minimum:0,maximum:1},demand:{type:"number",minimum:0}},required:["providerID","active","queued","max","utilization","demand"],additionalProperties:!1},L={type:"object",properties:{timestamp:{type:"integer",minimum:0},providerID:{type:"string"},kind:{type:"string",enum:["acquired","queued","released","dequeued"]},sessionID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0}},required:["timestamp","providerID","kind","sessionID","active","queued"],additionalProperties:!1},I={type:"object",properties:{},additionalProperties:!1},E={id:"request-concurrency-queue",methods:{status:{input:I,output:{type:"object",properties:{providers:{type:"array",items:B},transitions:{type:"array",items:L}},required:["providers","transitions"],additionalProperties:!1}}},events:{changed:{schema:I}}},v=[{percent:0,hue:145,saturation:60,lightness:28},{percent:100,hue:120,saturation:60,lightness:60},{percent:150,hue:60,saturation:85,lightness:70},{percent:200,hue:32,saturation:95,lightness:55},{percent:250,hue:12,saturation:90,lightness:68},{percent:300,hue:0,saturation:70,lightness:35}];function D(t){const r=Number.isFinite(t)?Math.max(0,t):0,i=v[v.length-1];if(r>=i.percent)return A(i);for(let n=1;n<v.length;n+=1){const s=v[n-1],a=v[n];if(r>a.percent)continue;const o=(r-s.percent)/(a.percent-s.percent);return`hsl(${Math.round(q(s.hue,a.hue,o))} ${Math.round(q(s.saturation,a.saturation,o))}% ${Math.round(q(s.lightness,a.lightness,o))}%)`}return A(i)}function A(t){return`hsl(${t.hue} ${t.saturation}% ${t.lightness}%)`}function q(t,r,i){return t+(r-t)*i}const N=5e3;function O(t){return{providerID:t.providerID,active:t.active,queued:t.queued,max:t.max,total:t.active+t.queued,utilization:z(t.utilization),demand:z(t.demand),utilizationColor:D(t.utilization*100),demandColor:D(t.demand*100)}}function R(t){return t.providers.map(O)}const F=20;function U(t,r=F){return t.transitions.slice(-r).reverse().map(j)}function j(t){return{time:Y(t.timestamp),providerID:t.providerID,kind:t.kind,sessionID:t.sessionID,active:t.active,queued:t.queued}}function H(t,r,i={}){const n=t(),s=i.refetchIntervalMs??N;let a=!1,o=0;const l=async()=>{const g=++o;let p;try{p=await n.status({},V(i.directory))}catch{!a&&g===o&&r(null);return}!a&&g===o&&r(p)};l();const d=n.events.on("changed",()=>{l()}),u=setInterval(()=>{l()},s);return()=>{a=!0,clearInterval(u),d()}}function V(t){return t===void 0?void 0:{location:{directory:t}}}function z(t){return`${Math.round(t*100)}%`}function Y(t){const r=new Date(t),i=n=>String(n).padStart(2,"0");return`${i(r.getHours())}:${i(r.getMinutes())}:${i(r.getSeconds())}`}var J=e.template("<div class=request-concurrency-status-header aria-hidden=true><span>Provider</span><span>Active</span><span>Queued</span><span>Util</span><span>Demand"),Q=e.template("<div class=request-concurrency-feed><div class=request-concurrency-feed-title>Recent activity"),G=e.template("<div class=request-concurrency-status>"),K=e.template("<div class=request-concurrency-status-unavailable>Status unavailable"),W=e.template('<div class=request-concurrency-status-row><span class=request-concurrency-status-provider></span><span class=request-concurrency-status-active><span></span><span class=request-concurrency-status-max></span></span><span class=request-concurrency-status-queued></span><span class=request-concurrency-status-utilization title="Utilization: active / max"></span><span class=request-concurrency-status-demand title="Demand: (active + queued) / max">'),X=e.template("<div class=request-concurrency-feed-row><span class=request-concurrency-feed-time></span><span></span><span class=request-concurrency-feed-provider></span><span class=request-concurrency-feed-session></span><span class=request-concurrency-feed-counts>"),Z=e.template("<span class=request-concurrency-bar-items>"),ee=e.template('<button type=button class=request-concurrency-bar title="Open concurrency details"aria-label="Open concurrency details"><span class=request-concurrency-bar-label>Concurrency'),te=e.template("<span class=request-concurrency-bar-muted>Status unavailable"),ne=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider></span><span>"),re=e.template("<div class=request-concurrency-dialog>");const se="Status unavailable",ie={providers:[],transitions:[]};function b(t){return t===null?{unavailable:!0,rows:[],transitions:[]}:{unavailable:!1,rows:R(t),transitions:U(t)}}function k(t){const r=()=>b(t.snapshot);return(()=>{var i=G();return e.insert(i,e.createComponent(m.Show,{get when(){return!r().unavailable},get fallback(){return K()},get children(){return[e.createComponent(m.Show,{get when(){return r().rows.length>0},get children(){return J()}}),e.createComponent(m.For,{get each(){return r().rows},children:n=>(()=>{var s=W(),a=s.firstChild,o=a.nextSibling,l=o.firstChild,d=l.nextSibling,u=o.nextSibling,g=u.nextSibling,p=g.nextSibling;return e.insert(a,()=>n.providerID),e.insert(l,()=>n.active),e.insert(d,()=>` / ${n.max}`),e.insert(u,()=>n.queued),e.insert(g,()=>n.utilization),e.insert(p,()=>n.demand),e.effect(c=>{var y=n.demandColor,f=n.providerID,x=`${n.active} of ${n.max} slots in use`,S=n.utilizationColor,w=n.demandColor,$=`${n.queued} waiting`,C=n.utilizationColor,_=n.demandColor;return y!==c.e&&e.setStyleProperty(s,"border-left-color",c.e=y),f!==c.t&&e.setAttribute(a,"title",c.t=f),x!==c.a&&e.setAttribute(o,"title",c.a=x),S!==c.o&&e.setStyleProperty(l,"color",c.o=S),w!==c.i&&e.setStyleProperty(u,"color",c.i=w),$!==c.n&&e.setAttribute(u,"title",c.n=$),C!==c.s&&e.setStyleProperty(g,"color",c.s=C),_!==c.h&&e.setStyleProperty(p,"color",c.h=_),c},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0}),s})()}),e.createComponent(m.Show,{get when(){return r().transitions.length>0},get children(){var n=Q();return n.firstChild,e.insert(n,e.createComponent(m.For,{get each(){return r().transitions},children:s=>(()=>{var a=X(),o=a.firstChild,l=o.nextSibling,d=l.nextSibling,u=d.nextSibling,g=u.nextSibling;return e.insert(o,()=>s.time),e.insert(l,()=>s.kind),e.insert(d,()=>s.providerID),e.insert(u,()=>s.sessionID),e.insert(g,()=>`${s.active} active · ${s.queued} queued`),e.effect(p=>{var c=`request-concurrency-feed-kind is-${s.kind}`,y=s.providerID,f=s.sessionID;return c!==p.e&&e.className(l,p.e=c),y!==p.t&&e.setAttribute(d,"title",p.t=y),f!==p.a&&e.setAttribute(u,"title",p.a=f),p},{e:void 0,t:void 0,a:void 0}),a})()}),null),n}})]}})),i})()}function P(t){const r=()=>b(t.snapshot);return e.createComponent(m.Show,{get when(){return r().unavailable||r().rows.length>0},get children(){var i=ee();return i.firstChild,e.addEventListener(i,"click",()=>t.onOpen()),e.insert(i,e.createComponent(m.Show,{get when(){return!r().unavailable},get fallback(){return te()},get children(){var n=Z();return e.insert(n,e.createComponent(m.For,{get each(){return r().rows},children:s=>(()=>{var a=ne(),o=a.firstChild,l=o.nextSibling;return e.insert(o,()=>s.providerID),e.insert(l,()=>`${s.total}/${s.max}`),e.effect(d=>{var u=s.demandColor,g=`${s.total} of ${s.max} slots in demand`;return u!==d.e&&e.setStyleProperty(l,"color",d.e=u),g!==d.t&&e.setAttribute(l,"title",d.t=g),d},{e:void 0,t:void 0}),a})()})),n}}),null),i}})}function ae(t){const r=h.usePlugin();return e.createComponent(r.ui.Dialog,{title:"Concurrency",size:"x-large",get children(){var i=re();return e.insert(i,e.createComponent(k,{get snapshot(){return t.snapshot()}})),i}})}function M(){const t=h.usePlugin(),[r,i]=m.createSignal(ie),[n,s]=m.createSignal(!1);m.createEffect(()=>{const o=t.servers.list().map(u=>t.servers.get(u)),l=o.find(u=>u?.builtin)??o.find(Boolean);if(!l)return;const d=H(()=>l.client.rpc(E),u=>{i(u),s(!0)});m.onCleanup(d)});const a=()=>{t.dialogs.open(()=>e.createComponent(ae,{snapshot:r}))};return e.createComponent(m.Show,{get when(){return n()},get children(){return e.createComponent(P,{get snapshot(){return r()},onOpen:a})}})}const oe=h.Plugin.define({setup(t){t.add(h.Slot,{at:"window.bottom",render:()=>e.createComponent(M,{})}),t.add(h.Style,T)}});exports.STATUS_UNAVAILABLE=se;exports.StatusBar=M;exports.StatusBarBody=P;exports.StatusBody=k;exports.default=oe;exports.statusBodyState=b;
