const $ = (s) => document.querySelector(s);
const $$ = (s) => document.querySelectorAll(s);

async function get(url) {
  const r = await fetch(url);
  const j = await r.json();
  if (!r.ok) throw new Error(j.error || r.statusText);
  return j;
}

/* ---- navigation ---- */
function show(view) {
  $$(".view").forEach(v => v.classList.toggle("on", v.id === "view-" + view));
  $$("#nav a").forEach(a => a.classList.toggle("on", a.dataset.view === view));
  $$("#seg button").forEach(b => b.classList.toggle("on", b.dataset.view === view));
  if (view === "bilan") loadBilan();
  if (view === "tests") loadTests();
}
$$("#nav a, #seg button").forEach(el => el.addEventListener("click", () => show(el.dataset.view)));

/* ---- vue générale ---- */
async function loadGeneral() {
  const [kpi, zones, stations] = await Promise.all([get("/api/kpi"), get("/api/zones"), get("/api/stations")]);
  $("#k-valides").textContent = kpi.valides.toLocaleString("fr-FR");
  $("#k-isolees").textContent = kpi.isolees.toLocaleString("fr-FR");
  $("#k-stations").textContent = kpi.stations + " · " + kpi.capteurs;

  // anneau
  const total = zones.total || 1, p1 = zones.zone1 / total;
  const C = 2 * Math.PI * 48;
  $("#donut").innerHTML = `
    <circle cx="60" cy="60" r="48" fill="none" stroke="#e5e5ea" stroke-width="18"/>
    <circle cx="60" cy="60" r="48" fill="none" stroke="#0a84ff" stroke-width="18"
      stroke-dasharray="${(p1*C).toFixed(1)} ${C.toFixed(1)}" transform="rotate(-90 60 60)" stroke-linecap="round"/>
    <circle cx="60" cy="60" r="48" fill="none" stroke="#30d158" stroke-width="18"
      stroke-dasharray="${((1-p1)*C).toFixed(1)} ${C.toFixed(1)}" stroke-dashoffset="${(-p1*C).toFixed(1)}"
      transform="rotate(-90 60 60)" stroke-linecap="round"/>
    <text x="60" y="58" text-anchor="middle" font-size="18" font-weight="700" fill="#1d1d1f">${Math.round(p1*100)}%</text>
    <text x="60" y="74" text-anchor="middle" font-size="9" fill="#8e8e93">zone 1</text>`;
  $("#lz1").textContent = zones.zone1.toLocaleString("fr-FR");
  $("#lz2").textContent = zones.zone2.toLocaleString("fr-FR");

  $("#stations").innerHTML = stations.map(s =>
    `<li><i class="dot ${s.zone === 1 ? "z1" : "z2"}"></i>${s.code} · ${s.nom}<b>zone ${s.zone}</b></li>`).join("");
}

/* ---- vue zones ---- */
async function loadZones() {
  const z = await get("/api/zones");
  $("#zone1").textContent = z.zone1.toLocaleString("fr-FR");
  $("#zone2").textContent = z.zone2.toLocaleString("fr-FR");
  $("#ztotal").textContent = z.total.toLocaleString("fr-FR");
}

/* ---- bilan XML ---- */
async function loadBilan() {
  const d = $("#b-debut").value, f = $("#b-fin").value;
  const b = await get(`/api/bilan?debut=${d}&fin=${f}`);
  $("#bilan-xml").textContent = b.xml;
  const doc = new DOMParser().parseFromString(b.xml, "text/xml");
  const jours = doc.getElementsByTagName("jour").length;
  const st = doc.getElementsByTagName("station").length;
  const gr = doc.getElementsByTagName("grandeur").length;
  $("#bilan-resume").innerHTML =
    `${jours} jour(s) · ${st} station(s) · ${gr} grandeurs<br>` +
    `<span class="muted">well-formed ✓ — min / max / moyenne / nbMesures par jour, station et grandeur</span>`;
}
$("#b-go").addEventListener("click", loadBilan);

/* ---- tests ---- */
async function loadTests() {
  const [e1, e2] = await Promise.all([get("/api/explain"), get("/api/explain_zone1")]);
  $("#ex1").textContent = e1.plan;
  $("#ex2").textContent = e2.plan;
}

/* ---- init ---- */
loadGeneral();
setInterval(loadGeneral, 15000);
