# AutoPulse AI Executive Dashboard with Ops & Cost Intelligence tab
# Co-authored with CoCo
import streamlit as st
import pandas as pd
import numpy as np
import json
import re
import os
from datetime import datetime, timezone

# ============================================================
# AUTOPULSE AI — Executive Battery Risk Command Center
# Snowflake Streamlit / Streamlit in Snowflake  (CORRECTED BUILD)
#
# Fixes vs. previous version:
#  1. Failure-probability metric now reads the real column
#     FAILURE_PROBABILITY_PCT (0-100 scale) instead of the
#     non-existent FAILURE_PROBABILITY (0-1), which is why the
#     "PREDICTED FAILURES" tile always showed 0.
#  2. Risk tiles re-keyed to values that exist in the data
#     (highest level present = MEDIUM; there is no HIGH/CRITICAL).
#  3. CRITICAL is now a probability RULE (>=60%) so the tile is
#     meaningful rather than structurally always-zero.
#  4. Risk-trend chart uses VEHICLE_EVENT_CONTEXT.event_date
#     (a real time series) instead of the single prediction date.
#  5. Distinct vehicle counting; probability normalization; a
#     supplier-aware 30-day watchlist.
# ============================================================

st.set_page_config(
    page_title="AutoPulse AI | Battery Risk Intelligence",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="collapsed",
)

# -----------------------------
# CONFIGURATION
# -----------------------------
DATABASE = "AUTOPULSE_AI"
CURATED_SCHEMA = "CURATED"
WH = "AUTOPULSE_WH"  # default; overridden after session init

TABLE_VEHICLES = f"{DATABASE}.{CURATED_SCHEMA}.VEHICLE_BATTERY_360"
TABLE_PREDICTION = f"{DATABASE}.{CURATED_SCHEMA}.VEHICLE_BATTERY_PREDICTION"
TABLE_RCA = f"{DATABASE}.{CURATED_SCHEMA}.VEHICLE_BATTERY_RCA"
TABLE_EVENTS = f"{DATABASE}.{CURATED_SCHEMA}.VEHICLE_EVENT_CONTEXT"

AGENT_DATABASE = DATABASE
AGENT_SCHEMA = "CURATED"
BATTERY_AGENT = "AUTOPULSE_BATTERY_AGENT"
DQ_AGENT = "AUTOPULSE_DQ_INTELLIGENCE"
RCA_AGENT = "AUTOPULSE_RCA_AGENT"
PREDICTIVE_AGENT = "AUTOPULSE_PREDICTIVE_AGENT"
OPS_AGENT = "AUTOPULSE_OPS_AGENT"
VQ_AGENT = "AUTOPULSE_VEHICLE_QUALITY_AGENT"

TABLE_VQ = f"{DATABASE}.{CURATED_SCHEMA}.VEHICLE_QUALITY_SCORECARD"

# Risk thresholds (percentage scale, 0-100)
WATCH_THRESHOLD = 40      # vehicles at/above this % form the active watchlist
CRITICAL_THRESHOLD = 60   # rule-based "critical" band

conn = st.connection("snowflake", ttl=os.getenv("SNOWFLAKE_CONNECTION_TTL"))
session = conn.session()

if session:
    try:
        WH = session.sql("SELECT CURRENT_WAREHOUSE()").collect()[0][0] or WH
    except Exception:
        pass
    try:
        session.sql(f"USE WAREHOUSE {WH}").collect()
    except Exception as e:
        current_role = "UNKNOWN"
        try:
            current_role = session.sql("SELECT CURRENT_ROLE()").collect()[0][0]
        except Exception:
            pass
        st.error(
            f"**Warehouse Access Error**\n\n"
            f"The warehouse `{WH}` does not exist or the current role "
            f"`{current_role}` does not have USAGE on it.\n\n"
            f"**To fix:** run one of the following as ACCOUNTADMIN:\n"
            f"```sql\nGRANT USAGE ON WAREHOUSE {WH} TO ROLE {current_role};\n```\n"
            f"Or switch this workspace to a role that already has access "
            f"(e.g. ACCOUNTADMIN, AUTOPULSE_VIEWER, AUTOPULSE_COMMON)."
        )
        st.stop()

# -----------------------------
# PREMIUM DARK THEME
# -----------------------------
st.markdown("""
<style>
:root {
    --bg: #02070d;
    --panel: #07111b;
    --panel2: #0a1622;
    --line: #173044;
    --text: #f5f9ff;
    --muted: #8fa5b8;
    --blue: #00a8ff;
    --cyan: #16d9ff;
    --purple: #8b5cf6;
    --green: #19e875;
    --red: #ff3b58;
    --amber: #ffad18;
}
html, body, [data-testid="stAppViewContainer"] {
    background:
      radial-gradient(circle at 76% 8%, rgba(0,126,255,.10), transparent 30%),
      radial-gradient(circle at 28% 0%, rgba(122,40,255,.08), transparent 25%),
      #02070d !important;
    color: var(--text) !important;
}
[data-testid="stHeader"] { background: rgba(2,7,13,.82) !important; }
[data-testid="stToolbar"] { visibility: hidden; height: 0; }
.block-container { max-width: 1720px !important; padding: 0.65rem 1.05rem 1.1rem !important; }
section[data-testid="stSidebar"] { display:none; }
.ap-top { position: relative; overflow: hidden; border: 1px solid #15324b; border-radius: 18px; min-height: 108px; padding: 20px 28px; background: linear-gradient(100deg,#030a11,#061320 50%,#07101b); box-shadow: 0 0 35px rgba(0,125,255,.07); }
.ap-brand { position: relative; z-index: 4; display:flex; align-items:center; gap:16px; }
.ap-logo { width:58px;height:58px;border-radius:16px; display:flex;align-items:center;justify-content:center; font-size:34px; background:linear-gradient(145deg,#07192b,#04101b); border:1px solid #007cff; box-shadow:0 0 25px rgba(0,168,255,.30), inset 0 0 18px rgba(0,168,255,.10); }
.ap-title { font-size:28px;font-weight:900;letter-spacing:.4px;line-height:1.0; }
.ap-title span { color:#00a8ff; }
.ap-sub { color:#8fa5b8;font-size:12px;margin-top:7px;letter-spacing:.8px; }
.live { margin-left:auto; display:flex;align-items:center;gap:9px; color:#dfffe9;font-size:12px;font-weight:800; padding:10px 15px;border:1px solid #173c34;border-radius:999px; background:rgba(5,35,28,.65); }
.live-dot {width:9px;height:9px;border-radius:50%;background:#18eb79;box-shadow:0 0 13px #18eb79;}
.ap-time { color:#7e93a6;font-size:11px;margin-left:15px; }
.wave { position:absolute;left:0;right:0;bottom:-3px;height:74px;opacity:.65;pointer-events:none; overflow:hidden; }
.wave svg { width:160%;height:100%; animation: drift 28s linear infinite; }
.wave2 svg { animation-duration:38s; opacity:.55; transform:translateX(-18%); }
@keyframes drift { from {transform:translateX(0)} to {transform:translateX(-22%)} }
.agent-rail { border:1px solid #153047;border-radius:16px; background:linear-gradient(180deg,#07121d,#040b12); padding:14px;height:100%; box-shadow:0 10px 35px rgba(0,0,0,.20); }
.agent-head {font-size:15px;font-weight:900;margin-bottom:10px;}
.agent-option { padding:11px 12px;border:1px solid #183249;border-radius:12px;margin:7px 0; background:#06101a;color:#dbe8f3;font-size:12px; }
.agent-option.active { border-color:#008dff; background:linear-gradient(100deg,rgba(0,125,255,.20),rgba(0,72,130,.08)); box-shadow:0 0 18px rgba(0,125,255,.12); }
.agent-icon {font-size:20px;margin-right:8px;}
.agent-small {color:#71899d;font-size:10px;margin-top:3px;}
.prompt { border:1px solid #17334b;border-radius:10px;padding:9px 10px;margin:6px 0; color:#9eb3c5;background:#040c14;font-size:11px; }
.chatbox { border:1px solid #17334b;border-radius:15px; background:#030b12;padding:12px; min-height:280px;max-height:430px;overflow:auto; }
.chat-user { background:linear-gradient(100deg,#075ac8,#0b3e82); border-radius:12px 12px 3px 12px;padding:10px 12px;margin:7px 0 7px 20px; font-size:12px; }
.chat-ai { background:#08141f;border:1px solid #17354c; border-radius:12px 12px 12px 3px;padding:11px 12px;margin:7px 20px 7px 0; font-size:12px;line-height:1.45; }
.chat-meta {font-size:9px;color:#6f8799;margin-bottom:4px;}
.status { border:1px solid #163249;border-radius:14px;padding:10px 16px; background:#06101a;display:flex;gap:28px;align-items:center; margin:12px 0 14px; }
.status-item {display:flex;align-items:center;gap:8px;color:#a9bdcc;font-size:11px;}
.status-item b {color:#20f184;}
.status-icon {font-size:18px;}
.kpi { position:relative;overflow:hidden; min-height:132px;border:1px solid #17364e;border-radius:16px; background:linear-gradient(145deg,#07121c,#040b12); padding:18px 19px; box-shadow:inset 0 1px 0 rgba(255,255,255,.025),0 10px 30px rgba(0,0,0,.15); }
.kpi:after {content:"";position:absolute;right:-40px;top:-50px;width:130px;height:130px;border-radius:50%;background:rgba(0,155,255,.06);}
.kpi-label {font-size:10px;color:#8ca7bb;font-weight:800;letter-spacing:.8px;}
.kpi-value {font-size:30px;font-weight:900;margin-top:8px;letter-spacing:-.5px;}
.kpi-foot {font-size:10px;color:#668096;margin-top:7px;}
.kpi-blue{border-top:2px solid #00a8ff}.kpi-red{border-top:2px solid #ff3150}.kpi-amber{border-top:2px solid #ffad18}.kpi-green{border-top:2px solid #18e879}
.kpi-icon {position:absolute;right:17px;top:15px;font-size:27px;opacity:.85}
.panel { border:1px solid #173247;border-radius:16px; background:linear-gradient(145deg,#07121c,#040b12); padding:14px 16px;min-height:100%; }
.panel-title {font-size:13px;font-weight:900;letter-spacing:.25px;margin-bottom:10px;}
.panel-sub {font-size:9px;color:#71899c;margin-top:-6px;margin-bottom:10px;}
.section-title {font-size:18px;font-weight:900;margin:17px 0 9px;}
.attn { color:#ff4e67;font-weight:900; }
.dark-table {width:100%;border-collapse:collapse;font-size:10px;}
.dark-table th {color:#7891a4;text-align:center;padding:9px 7px;border-bottom:1px solid #173248;font-weight:800;}
.dark-table td {padding:9px 7px;border-bottom:1px solid #102435;color:#d7e3ec;text-align:center;}
.badge {padding:4px 7px;border-radius:6px;font-size:9px;font-weight:900;}
.badge-critical{color:#ff6379;background:rgba(255,50,75,.13);border:1px solid rgba(255,50,75,.28)}
.badge-high{color:#ffc04e;background:rgba(255,171,20,.12);border:1px solid rgba(255,171,20,.25)}
.badge-medium{color:#f5d84e;background:rgba(245,216,78,.10);border:1px solid rgba(245,216,78,.22)}
.badge-low{color:#36f38e;background:rgba(25,232,117,.10);border:1px solid rgba(25,232,117,.22)}
.footer {text-align:center;color:#526b7d;font-size:9px;margin-top:15px;padding:10px;}
.ap-top:before { content:""; position:absolute; width:280px; height:280px; border-radius:50%; left:-180px; top:-150px; background:radial-gradient(circle, rgba(255,255,255,.34) 0%, rgba(255,255,255,.12) 18%, rgba(92,197,255,.07) 40%, transparent 72%); filter:blur(7px); pointer-events:none; animation:lightSweep 18s ease-in-out infinite; z-index:1; }
.ap-top:after { content:""; position:absolute; width:170px; height:170px; border-radius:50%; right:-100px; bottom:-110px; background:radial-gradient(circle, rgba(255,255,255,.18) 0%, rgba(70,180,255,.07) 38%, transparent 72%); filter:blur(8px); animation:lightSweep2 23s ease-in-out infinite; pointer-events:none; }
@keyframes lightSweep { 0%,100% { transform:translateX(0) translateY(0); opacity:.45; } 50% { transform:translateX(1180px) translateY(34px); opacity:.82; } }
@keyframes lightSweep2 { 0%,100% { transform:translateX(0); opacity:.30; } 50% { transform:translateX(-650px) translateY(-40px); opacity:.70; } }
.live-dot { animation:pulseLive 1.8s ease-in-out infinite; }
@keyframes pulseLive { 0%,100% { transform:scale(.85); opacity:.65; } 50% { transform:scale(1.25); opacity:1; } }
.status { background:linear-gradient(90deg,rgba(255,255,255,.035),rgba(5,18,29,.95),rgba(255,255,255,.025)); }
.status-item b { animation:statusPulse 2.4s ease-in-out infinite; }
@keyframes statusPulse { 0%,100% { opacity:.65; } 50% { opacity:1; text-shadow:0 0 10px rgba(25,232,117,.45); } }
.agent-rail { position:sticky; top:12px; min-height:900px; background: radial-gradient(circle at 50% 0%,rgba(0,168,255,.10),transparent 30%), linear-gradient(180deg,#06111b,#02080e 78%); }
.agent-option { transition:all .2s ease; }
.agent-option:hover { border-color:#00a8ff; transform:translateX(2px); box-shadow:0 0 18px rgba(0,168,255,.10); }
.agent-icon {font-size:25px;}
.chatbox { background: radial-gradient(circle at 80% 0%,rgba(255,255,255,.045),transparent 28%), #02080e; }
.chat-ai { box-shadow:inset 0 0 20px rgba(0,168,255,.025); }
.live-signal { height:7px; margin-top:9px; border-radius:99px; overflow:hidden; background:#07141f; border:1px solid #17354a; }
.live-signal span { display:block; width:32%; height:100%; border-radius:99px; background:linear-gradient(90deg,transparent,#00c8ff,#ffffff,#8b5cf6,transparent); filter:blur(.2px); animation:signalMove 5.5s linear infinite; }
@keyframes signalMove { from { transform:translateX(-120%); } to { transform:translateX(420%); } }
[data-testid="stVerticalBlockBorderWrapper"] { background: radial-gradient(circle at 100% 0%,rgba(0,168,255,.08),transparent 35%), linear-gradient(180deg,#06131e,#02080e) !important; border:1px solid #17384f !important; border-radius:16px !important; box-shadow:0 12px 40px rgba(0,0,0,.25) !important; overflow:visible !important; }
[data-testid="stVerticalBlockBorderWrapper"] > div { overflow:visible !important; }
[data-testid="stVerticalBlock"] { overflow:visible !important; }
.assistant-title { font-size:17px; font-weight:950; letter-spacing:.5px; color:#f4f9ff; }
.assistant-title span { color:#19e875; font-size:9px; letter-spacing:1.2px; margin-left:7px; vertical-align:middle; }
.assistant-sub { color:#7891a4; font-size:10px; margin:4px 0 14px; }
.rail-label { color:#7f98ab; font-size:9px; font-weight:900; letter-spacing:1.2px; margin:12px 0 7px; }
.agent-description { color:#688296; font-size:9px; margin:-4px 0 5px 8px; }
.connected-agent { margin:10px 0; padding:8px 10px; border:1px solid #153a50; border-radius:9px; background:#04101a; color:#19e875; font-size:8px; font-weight:900; letter-spacing:.7px; }
.connected-agent span { color:#7590a3; font-weight:500; letter-spacing:0; }
.chat-label { margin-top:14px; }
.chat-empty,.chat-ai-final,.chat-user-final { border-radius:11px; padding:9px 10px; margin:6px 0; font-size:10px; line-height:1.45; }
.chat-empty,.chat-ai-final { background:linear-gradient(135deg,#071724,#04101a); border:1px solid #15364d; color:#dce9f4; }
.chat-user-final { background:linear-gradient(135deg,#075eb9,#073b78); border:1px solid #168ee0; color:#fff; }
.chat-meta { font-size:8px; font-weight:900; color:#6f93ad; letter-spacing:.7px; margin-bottom:3px; }
.chat-user-final .chat-meta { color:#bfe8ff; }
.chat-main { color:#dce9f4; }
.agent-status-strip { margin-top:9px; padding:7px 9px; border-radius:8px; background:#04110c; border:1px solid #17462e; color:#7fa995; font-size:8px; }
.agent-status-strip .live-dot { display:inline-block; margin-right:5px; }
[data-testid="stTextInput"] label { display:none !important; }
[data-testid="stTextInput"] > div > div { background:#020a11 !important; border:1px solid #20445b !important; border-radius:10px !important; }
[data-testid="stTextInput"] input { background:#020a11 !important; color:#ffffff !important; -webkit-text-fill-color:#ffffff !important; caret-color:#00c8ff !important; font-size:10px !important; }
[data-testid="stTextInput"] input::placeholder { color:#6f899c !important; opacity:1 !important; }
[data-testid="stTextInput"] > div > div:focus-within { border-color:#00a8ff !important; box-shadow:0 0 0 1px rgba(0,168,255,.20),0 0 18px rgba(0,168,255,.08) !important; }
[data-testid="stChatInput"] { background:#030b12 !important; border:1px solid #1b3d55 !important; border-radius:14px !important; box-shadow:0 0 24px rgba(0,168,255,.08) !important; }
[data-testid="stChatInput"] > div { background:#030b12 !important; }
[data-testid="stChatInput"] textarea, [data-testid="stChatInput"] input { background:#030b12 !important; color:#f5f9ff !important; -webkit-text-fill-color:#f5f9ff !important; caret-color:#00c8ff !important; }
[data-testid="stChatInput"] textarea::placeholder, [data-testid="stChatInput"] input::placeholder { color:#7891a4 !important; opacity:1 !important; }
[data-testid="stChatInput"] button { background:#0b2232 !important; color:#00c8ff !important; border:1px solid #1b4d6b !important; }
[data-testid="stChatInput"] button:hover {background:#0d3146 !important;}
[data-testid="stSelectbox"] > div, [data-baseweb="select"] > div, [data-baseweb="input"] > div { background:#06111a !important; color:#f5f9ff !important; border-color:#17364e !important; }
[data-baseweb="popover"] { background:#06111a !important; border:1px solid #17364e !important; }
[data-baseweb="popover"] li { color:#f5f9ff !important; }
[data-baseweb="popover"] li:hover { background:#0a1e2e !important; }
[data-baseweb="select"] [data-baseweb="tag"] { background:#0a1e2e !important; }
[data-baseweb="select"] span {color:#eaf5ff !important;}
[data-baseweb="popover"] {background:#06111a !important;}
[data-baseweb="menu"] {background:#06111a !important;}
[data-baseweb="menu"] * {color:#eaf5ff !important;}
[data-testid="stButton"] button { background:#06111a !important; color:#dce9f5 !important; border:1px solid #17364e !important; border-radius:10px !important; min-height:40px !important; font-weight:800 !important; }
[data-testid="stButton"] button:hover { border-color:#00a8ff !important; color:#ffffff !important; box-shadow:0 0 16px rgba(0,168,255,.12) !important; }
.agent-nav [data-testid="stButton"] button { text-align:left !important; padding:8px 10px !important; font-size:11px !important; min-height:36px !important; }
.agent-card-btn [data-testid="stButton"] button { text-align:left !important; padding:10px 12px !important; min-height:58px !important; }
.chat-scroll { max-height:410px; overflow-y:auto; padding-right:4px; }
.page-head{display:flex;align-items:center;gap:14px;margin:8px 0 14px;padding:14px 17px;border:1px solid #173247;border-radius:15px;background:linear-gradient(90deg,#07121c,#040b12);box-shadow:0 0 28px rgba(0,168,255,.06)}
.page-title{font-size:25px;font-weight:900}.page-sub{font-size:10px;color:#7891a4;margin-top:4px;letter-spacing:.4px}
</style>
""", unsafe_allow_html=True)

# -----------------------------
# HELPERS
# -----------------------------
def qdf(sql):
    try:
        return session.sql(sql).to_pandas()
    except Exception:
        return pd.DataFrame()

def discover_agents():
    try:
        df = session.sql(f"SHOW AGENTS IN DATABASE {AGENT_DATABASE}").to_pandas()
        if df.empty:
            return {}
        cols = {str(c).upper(): c for c in df.columns}
        name_col = cols.get("NAME")
        db_col = cols.get("DATABASE_NAME")
        schema_col = cols.get("SCHEMA_NAME")
        result = {}
        for _, row in df.iterrows():
            name = str(row[name_col]) if name_col else ""
            db = str(row[db_col]) if db_col else AGENT_DATABASE
            schema = str(row[schema_col]) if schema_col else AGENT_SCHEMA
            if name:
                result[name.upper()] = f"{db}.{schema}.{name}"
        return result
    except Exception:
        return {}

def resolve_agent(preferred_name, keywords=()):
    discovered = discover_agents()
    preferred = preferred_name.upper()
    if preferred in discovered:
        return discovered[preferred]
    for name, fq in discovered.items():
        if any(k.upper() in name for k in keywords):
            return fq
    return f"{AGENT_DATABASE}.{AGENT_SCHEMA}.{preferred_name}"

def run_cortex_agent(agent_fqn, question):
    body = {"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],
            "stream": False, "background": False}
    body_json = json.dumps(body, ensure_ascii=False)
    agent_sql = str(agent_fqn).replace("'", "''")
    if "$$" in body_json:
        body_literal = "'" + body_json.replace("'", "''") + "'"
    else:
        body_literal = "$$" + body_json + "$$"
    sql = f"""
        SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('{agent_sql}', {body_literal}, TRUE) AS RESPONSE
    """
    try:
        result = session.sql(sql).to_pandas()
        if result.empty:
            return f"No response returned by {agent_fqn}.", False
        raw = result.iloc[0, 0]
        obj = json.loads(str(raw)) if isinstance(raw, str) else raw
        texts = []
        def walk(x):
            if isinstance(x, dict):
                for k, v in x.items():
                    if k == "text" and isinstance(v, str) and v.strip():
                        texts.append(v.strip())
                    elif k != "thinking":
                        walk(v)
            elif isinstance(x, list):
                for item in x:
                    walk(item)
        walk(obj)
        warnings = []
        if isinstance(obj, dict):
            for w in obj.get("warnings", []) or []:
                if isinstance(w, dict) and w.get("message"):
                    warnings.append(str(w["message"]))
        answer = "\n\n".join(dict.fromkeys(texts)).strip() or str(raw)
        if warnings:
            answer += "\n\n⚠️ Agent warning: " + " | ".join(warnings)
        return answer, True
    except Exception as e:
        return (f"Could not run **{agent_fqn}**.\n\nSnowflake returned: `{e}`\n\n"
                "Check that the Streamlit owner's role has access to the Agent and its tools.", False)

def safe_num(v, default=0):
    try:
        if pd.isna(v):
            return default
        return float(v)
    except Exception:
        return default

def fmt_int(v):
    return f"{int(round(safe_num(v))):,}"

def fmt_pct(v):
    return f"{safe_num(v):.1f}%"

def pick_col(df, candidates):
    if df is None or df.empty:
        return None
    cols = {str(c).upper(): c for c in df.columns}
    for c in candidates:
        if c.upper() in cols:
            return cols[c.upper()]
    return None

# Single source of truth for the failure-probability column names.
# The real curated column is FAILURE_PROBABILITY_PCT (0-100 scale).
PROB_CANDS = ["FAILURE_PROBABILITY_PCT", "FAILURE_PROB_PCT",
              "FAILURE_PROBABILITY", "FAILURE_PROB", "PREDICTED_FAILURE_PROBABILITY"]

def numeric_series(df, candidates):
    c = pick_col(df, candidates)
    if c:
        return pd.to_numeric(df[c], errors="coerce")
    return pd.Series(dtype=float)

def prob_pct_series(df):
    """Return failure probability on a 0-100 scale, regardless of source scale."""
    s = numeric_series(df, PROB_CANDS).dropna()
    if not s.empty and s.max() <= 1.0:   # stored as 0-1 fraction
        s = s * 100.0
    return s

def risk_counts(df):
    c = pick_col(df, ["RISK_LEVEL", "RISK", "PREDICTED_RISK_LEVEL", "BATTERY_RISK_LEVEL"])
    if not c or df.empty:
        return {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0}
    s = df[c].astype(str).str.upper().str.strip()
    return {k: int((s == k).sum()) for k in ["CRITICAL", "HIGH", "MEDIUM", "LOW"]}

def dark_table(df, max_rows=8):
    if df is None or df.empty:
        st.markdown('<div style="color:#71899c;font-size:11px;padding:18px">No records available.</div>', unsafe_allow_html=True)
        return
    d = df.head(max_rows).copy()
    rows = []
    for _, r in d.iterrows():
        vals = []
        for x in r.values:
            if pd.isna(x):
                vals.append("—")
            elif isinstance(x, (float, np.floating)):
                vals.append(f"{x:.2f}")
            else:
                vals.append(str(x)[:32])
        rows.append(vals)
    headers = [str(x).replace("_", " ") for x in d.columns]
    html = '<table class="dark-table"><thead><tr>' + ''.join(f'<th>{h}</th>' for h in headers) + '</tr></thead><tbody>'
    for row in rows:
        html += '<tr>' + ''.join(f'<td>{x}</td>' for x in row) + '</tr>'
    html += '</tbody></table>'
    st.markdown(html, unsafe_allow_html=True)

# -----------------------------
# LOAD CURATED DATA
# -----------------------------
@st.cache_data(ttl=60, show_spinner=False)
def load_data():
    vehicles = qdf(f"SELECT * FROM {TABLE_VEHICLES} LIMIT 20000")
    prediction = qdf(f"SELECT * FROM {TABLE_PREDICTION} LIMIT 20000")
    rca = qdf(f"SELECT * FROM {TABLE_RCA} LIMIT 20000")
    events = qdf(f"SELECT * FROM {TABLE_EVENTS} LIMIT 20000")
    return vehicles, prediction, rca, events

vehicles, prediction, rca, events = load_data()

# -----------------------------
# STATE FILTER (global drill-down)
# -----------------------------
state_col_v = pick_col(vehicles, ["STATE", "STATE_AB"])
state_col_e = pick_col(events, ["STATE", "STATE_AB"])
state_col_r = pick_col(rca, ["STATE", "STATE_AB"])
_all_states = set()
if state_col_v and not vehicles.empty:
    _all_states |= set(vehicles[state_col_v].dropna().unique())
if state_col_e and not events.empty:
    _all_states |= set(events[state_col_e].dropna().unique())
ALL_STATES = sorted(_all_states)

if "state_filter" not in st.session_state:
    st.session_state.state_filter = "All States"

# Build CAR_ID → STATE lookup for tables without STATE column
_vid_col = pick_col(vehicles, ["CAR_ID", "VEHICLE_ID", "VIN"])
_vst_col = pick_col(vehicles, ["STATE", "STATE_AB"])
_vehicle_state_df = pd.DataFrame()
if _vid_col and _vst_col and not vehicles.empty:
    _vsd = vehicles[[_vid_col, _vst_col]].drop_duplicates(subset=[_vid_col]).copy()
    _vsd = _vsd.rename(columns={_vid_col: "_JOIN_ID", _vst_col: "_STATE"})
    # Normalize join key to float then int to handle Decimal/int64/float64 mismatches
    _vsd["_JOIN_ID"] = pd.to_numeric(_vsd["_JOIN_ID"], errors="coerce")
    _vehicle_state_df = _vsd.dropna(subset=["_JOIN_ID"])

def apply_state_filter(df, col_name=None):
    sel = st.session_state.state_filter
    if sel == "All States" or not sel:
        return df
    if df is None or df.empty:
        return df
    c = col_name or pick_col(df, ["STATE", "STATE_AB"])
    if c and c in df.columns:
        return df[df[c] == sel].copy()
    # Fallback: merge with vehicles to get STATE, then filter
    jc = pick_col(df, ["CAR_ID", "VEHICLE_ID", "VIN"])
    if jc and not _vehicle_state_df.empty:
        tmp = df.copy()
        tmp["_MERGE_KEY"] = pd.to_numeric(tmp[jc], errors="coerce")
        merged = tmp.merge(_vehicle_state_df, left_on="_MERGE_KEY", right_on="_JOIN_ID", how="inner")
        filtered = merged[merged["_STATE"] == sel].drop(
            columns=["_JOIN_ID", "_STATE", "_MERGE_KEY"], errors="ignore"
        )
        return filtered
    return df

# -----------------------------
# METRICS  (all derived from real curated columns)
# -----------------------------
vehicle_id_col = pick_col(vehicles, ["CAR_ID", "VEHICLE_ID", "VIN", "VEHICLE_KEY"])
total_vehicles = int(vehicles[vehicle_id_col].nunique()) if vehicle_id_col and not vehicles.empty else len(vehicles)

pred_id_col = pick_col(prediction, ["CAR_ID", "VEHICLE_ID", "VIN"])
vehicles_scored = int(prediction[pred_id_col].nunique()) if pred_id_col and not prediction.empty else len(prediction)

rc = risk_counts(prediction)
critical_lvl = rc["CRITICAL"]     # from risk_level (currently 0 - no such data)
high_lvl = rc["HIGH"]             # from risk_level (currently 0)
medium = rc["MEDIUM"]             # 35
low = rc["LOW"]                   # 5,241

_prob = prob_pct_series(prediction)
max_prob = float(_prob.max()) if not _prob.empty else 0.0
avg_prob = float(_prob.mean()) if not _prob.empty else 0.0
watchlist = int((_prob >= WATCH_THRESHOLD).sum())        # 35
critical_rule = int((_prob >= CRITICAL_THRESHOLD).sum())  # rule-based critical
coverage_pct = (vehicles_scored / max(total_vehicles, 1)) * 100

# -----------------------------
# SECONDARY PAGE RENDERERS
# -----------------------------
def render_page_header(title, subtitle, icon):
    st.markdown(f'''<div class="page-head"><div style="font-size:30px">{icon}</div><div><div class="page-title">{title}</div><div class="page-sub">{subtitle}</div></div></div>''', unsafe_allow_html=True)

def vega_bar(df, x, y, color_range=("#00c8ff", "#8b5cf6", "#ffad18", "#ff3150"), horizontal=False):
    if df is None or df.empty:
        st.info("No data available for this view.")
        return
    if horizontal:
        enc = {"y": {"field": x, "type": "nominal", "sort": "-x", "axis": {"labelColor": "#d7e3ec", "gridColor": "#173044"}},
               "x": {"field": y, "type": "quantitative", "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044"}}}
    else:
        enc = {"x": {"field": x, "type": "nominal", "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044"}},
               "y": {"field": y, "type": "quantitative", "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044"}}}
    enc["color"] = {"field": y, "type": "quantitative", "scale": {"range": list(color_range)}}
    enc["tooltip"] = [{"field": x, "type": "nominal"}, {"field": y, "type": "quantitative"}]
    spec = {"mark": {"type": "bar", "cornerRadiusEnd": 5}, "encoding": enc, "background": "#07121c", "config": {"view": {"stroke": "#173247"}}}
    st.vega_lite_chart(df, spec, use_container_width=True)

def vega_line(df, x, y, color="#00c8ff"):
    if df is None or df.empty:
        st.info("No data available for this view.")
        return
    spec = {
        "mark": {"type": "line", "strokeWidth": 2, "point": {"filled": True, "size": 30}},
        "encoding": {
            "x": {"field": x, "type": "temporal", "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044", "format": "%b %d"}},
            "y": {"field": y, "type": "quantitative", "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044"}},
            "color": {"value": color},
            "tooltip": [{"field": x, "type": "temporal"}, {"field": y, "type": "quantitative", "format": ".4f"}]
        },
        "background": "#07121c",
        "config": {"view": {"stroke": "#173247"}}
    }
    st.vega_lite_chart(df, spec, use_container_width=True)

def dtc_trend_df():
    """Real time series from event history (predictions carry a single date)."""
    dcol = pick_col(events, ["EVENT_DATE", "DATE", "CREATED_AT"])
    if not dcol or events.empty:
        return pd.DataFrame()
    tmp = events.copy()
    tmp["_D"] = pd.to_datetime(tmp[dcol], errors="coerce").dt.date
    tmp = tmp.dropna(subset=["_D"]).groupby("_D").size().reset_index(name="EVENTS")
    return tmp.tail(30)

def build_watchlist(n=15, f_pred=None, f_rca=None):
    """Top-N risk-ranked vehicles with supplier pulled from RCA."""
    _p = f_pred if f_pred is not None else prediction
    _r = f_rca if f_rca is not None else rca
    if _p.empty:
        return pd.DataFrame()
    pcol = pick_col(_p, PROB_CANDS)
    idc = pick_col(_p, ["CAR_ID", "VEHICLE_ID"])
    if not pcol or not idc:
        return pd.DataFrame()
    keep = [c for c in [idc, pick_col(_p, ["VIN"]), pick_col(_p, ["PART_NUMBER"]),
                        pick_col(_p, ["RISK_LEVEL"]), pcol,
                        pick_col(_p, ["PREDICTED_FAILURE_DAYS"]),
                        pick_col(_p, ["ERROR_RATE_PCT"]),
                        pick_col(_p, ["TOTAL_EVENTS"])] if c]
    top = _p[keep].copy()
    top["_P"] = pd.to_numeric(top[pcol], errors="coerce").fillna(0)
    if top["_P"].max() <= 1.0:
        top["_P"] *= 100
    scol = pick_col(_r, ["SUPPLIER"])
    rca_id = pick_col(_r, ["CAR_ID", "VEHICLE_ID"])
    if scol and rca_id and idc:
        sup = _r[[rca_id, scol]].drop_duplicates(subset=[rca_id])
        top = top.merge(sup, left_on=idc, right_on=rca_id, how="left")
        if rca_id != idc and rca_id in top.columns:
            top = top.drop(columns=[rca_id])
    top = top.sort_values("_P", ascending=False).drop(columns=["_P"])
    return top.head(n)

def render_risk_prediction(fv=None, fp=None, fr=None, fe=None):
    _pred = fp if fp is not None else prediction
    _evt = fe if fe is not None else events
    # Recompute metrics from filtered data
    _rc = risk_counts(_pred)
    _critical_lvl, _high_lvl, _medium, _low = _rc["CRITICAL"], _rc["HIGH"], _rc["MEDIUM"], _rc["LOW"]
    _pp = prob_pct_series(_pred)
    _watchlist = int((_pp >= WATCH_THRESHOLD).sum())
    _critical_rule = int((_pp >= CRITICAL_THRESHOLD).sum())

    render_page_header("Risk & Prediction", "Fleet risk segmentation and predictive maintenance intelligence", "📈")
    _f_total = len(_pred)
    c1, c2, c3, c4 = st.columns(4, gap="medium")
    with c1:
        st.markdown(f'<div class="kpi kpi-blue"><div class="kpi-icon">🚘</div><div class="kpi-label">VEHICLES</div><div class="kpi-value">{fmt_int(_f_total)}</div><div class="kpi-foot">Predictions in scope</div></div>', unsafe_allow_html=True)
    with c2:
        st.markdown(f'<div class="kpi kpi-red"><div class="kpi-icon">🛑</div><div class="kpi-label">CRITICAL (≥{CRITICAL_THRESHOLD}%)</div><div class="kpi-value">{fmt_int(_critical_rule)}</div><div class="kpi-foot">Rule-based critical band</div></div>', unsafe_allow_html=True)
    with c3:
        st.markdown(f'<div class="kpi kpi-amber"><div class="kpi-icon">⚠️</div><div class="kpi-label">MEDIUM RISK</div><div class="kpi-value">{fmt_int(_medium)}</div><div class="kpi-foot">From RISK_LEVEL column</div></div>', unsafe_allow_html=True)
    with c4:
        st.markdown(f'<div class="kpi kpi-green"><div class="kpi-icon">🔮</div><div class="kpi-label">WATCHLIST (≥{WATCH_THRESHOLD}%)</div><div class="kpi-value">{fmt_int(_watchlist)}</div><div class="kpi-foot">Active monitoring</div></div>', unsafe_allow_html=True)
    st.markdown('<div class="section-title">Risk Distribution & DTC Activity Trend</div>', unsafe_allow_html=True)
    a, b = st.columns(2, gap="medium")
    with a:
        st.markdown('<div class="panel"><div class="panel-title">RISK LEVEL DISTRIBUTION</div>', unsafe_allow_html=True)
        risk_order = ["Critical", "High", "Medium", "Low"]
        risk_colors = ["#ff3150", "#ffad18", "#f5d84e", "#18e879"]
        rdf = pd.DataFrame({"Risk Level": risk_order,
                            "Vehicles": [_critical_lvl, _high_lvl, _medium, _low]})
        spec = {
            "mark": {"type": "bar", "cornerRadiusEnd": 5},
            "encoding": {
                "x": {"field": "Risk Level", "type": "nominal",
                       "sort": risk_order,
                       "axis": {"labelColor": "#d7e3ec", "gridColor": "#173044", "labelAngle": 0}},
                "y": {"field": "Vehicles", "type": "quantitative",
                       "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044", "format": ",d"}},
                "color": {"field": "Risk Level", "type": "nominal",
                           "scale": {"domain": risk_order, "range": risk_colors},
                           "legend": None},
                "tooltip": [{"field": "Risk Level", "type": "nominal"},
                            {"field": "Vehicles", "type": "quantitative", "format": ","}]
            },
            "background": "#07121c",
            "config": {"view": {"stroke": "#173247"}}
        }
        st.vega_lite_chart(rdf, spec, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)
    with b:
        st.markdown('<div class="panel"><div class="panel-title">DTC ACTIVITY TREND (LAST 30 DAYS)</div>', unsafe_allow_html=True)
        dcol = pick_col(_evt, ["EVENT_DATE", "DATE", "CREATED_AT"])
        if dcol and not _evt.empty:
            _tmp = _evt.copy()
            _tmp["_D"] = pd.to_datetime(_tmp[dcol], errors="coerce").dt.date
            _tmp = _tmp.dropna(subset=["_D"]).groupby("_D").size().reset_index(name="EVENTS").tail(30)
        else:
            _tmp = pd.DataFrame()
        if not _tmp.empty:
            _tmp["_D"] = pd.to_datetime(_tmp["_D"])
            spec = {
                "mark": {"type": "area", "line": {"color": "#00c8ff", "strokeWidth": 2},
                         "color": {"x1": 1, "y1": 1, "x2": 1, "y2": 0,
                                   "gradient": "linear",
                                   "stops": [{"offset": 0, "color": "rgba(0,200,255,0.01)"},
                                             {"offset": 1, "color": "rgba(0,200,255,0.25)"}]},
                         "point": {"filled": True, "size": 25, "color": "#00c8ff"}},
                "encoding": {
                    "x": {"field": "_D", "type": "temporal",
                           "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044",
                                    "format": "%b %d", "labelAngle": -30, "title": None}},
                    "y": {"field": "EVENTS", "type": "quantitative",
                           "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044",
                                    "format": ",d", "title": "Events"}},
                    "tooltip": [{"field": "_D", "type": "temporal", "title": "Date", "format": "%b %d, %Y"},
                                {"field": "EVENTS", "type": "quantitative", "title": "Events", "format": ","}]
                },
                "background": "#07121c",
                "config": {"view": {"stroke": "#173247"}},
                "height": 260
            }
            st.vega_lite_chart(_tmp, spec, use_container_width=True)
        else:
            st.info("No dated event records available.")
        st.markdown('</div>', unsafe_allow_html=True)
    st.markdown('<div class="section-title">30-Day Risk Watchlist (top vehicles by failure probability)</div>', unsafe_allow_html=True)
    st.markdown('<div class="panel">', unsafe_allow_html=True)
    st.caption("Note: a 100% error rate on 1 total event is small-sample noise, not a confirmed failure.")
    dark_table(build_watchlist(15, f_pred=_pred, f_rca=fr if fr is not None else rca), max_rows=15)
    st.markdown('</div>', unsafe_allow_html=True)

def render_dq():
    render_page_header("Data Quality", "DQ monitoring, data volume trends and pipeline readiness", "🛡️")

    dq_candidates = [f"{DATABASE}.DQ.DQ_RESULTS", f"{DATABASE}.{CURATED_SCHEMA}.DQ_RESULTS", f"{DATABASE}.RAW.DQ_RESULTS"]
    dq = pd.DataFrame()
    for t in dq_candidates:
        q = qdf(f"SELECT * FROM {t} LIMIT 20000")
        if not q.empty:
            dq = q
            break

    total_events = len(events)
    scored = vehicles_scored
    completeness = (scored / max(total_vehicles, 1)) * 100
    ecol = pick_col(events, ["EVENT_DATE", "DATE", "CREATED_AT"])
    day_span = 0
    if ecol and not events.empty:
        d = pd.to_datetime(events[ecol], errors="coerce").dt.date.dropna()
        day_span = int((max(d) - min(d)).days) + 1 if not d.empty else 0

    k1, k2, k3, k4 = st.columns(4, gap="medium")
    with k1: st.markdown(f'<div class="kpi kpi-blue"><div class="kpi-label">TELEMETRY RECORDS</div><div class="kpi-value">{fmt_int(total_events)}</div><div class="kpi-foot">VEHICLE_EVENT_CONTEXT rows loaded</div></div>', unsafe_allow_html=True)
    with k2: st.markdown(f'<div class="kpi kpi-green"><div class="kpi-label">DAYS OF DATA</div><div class="kpi-value">{fmt_int(day_span)}</div><div class="kpi-foot">Event date coverage</div></div>', unsafe_allow_html=True)
    with k3: st.markdown(f'<div class="kpi kpi-amber"><div class="kpi-label">VEHICLES SCORED</div><div class="kpi-value">{fmt_int(scored)}</div><div class="kpi-foot">Reached prediction stage</div></div>', unsafe_allow_html=True)
    with k4: st.markdown(f'<div class="kpi kpi-purple" style="border-top:2px solid #8b5cf6"><div class="kpi-label">PIPELINE COMPLETENESS</div><div class="kpi-value">{completeness:.0f}%</div><div class="kpi-foot">Scored / total fleet</div></div>', unsafe_allow_html=True)

    st.markdown('<div class="section-title">📈 Data Trends — Records Per Day</div>', unsafe_allow_html=True)
    st.markdown('<div class="panel"><div class="panel-title">DAILY TELEMETRY VOLUME & DTC ERROR EVENTS</div><div class="panel-sub">FROM VEHICLE_EVENT_CONTEXT</div>', unsafe_allow_html=True)
    daily = qdf(f"""
        SELECT event_date AS "DATE",
               COUNT(*) AS "TOTAL_RECORDS",
               COUNT(DISTINCT car_id) AS "VEHICLES",
               SUM(CASE WHEN dtc_code IS NOT NULL AND dtc_code <> '' THEN 1 ELSE 0 END) AS "DTC_ERROR_EVENTS"
        FROM {TABLE_EVENTS}
        GROUP BY event_date
        ORDER BY event_date
    """)
    if not daily.empty:
        chart_data = [{"date": str(r["DATE"]), "Total records": int(r["TOTAL_RECORDS"]),
                       "DTC error events": int(r["DTC_ERROR_EVENTS"])} for _, r in daily.iterrows()]
        spec = {
            "transform": [{"fold": ["Total records", "DTC error events"], "as": ["Series", "Value"]}],
            "mark": {"type": "line", "point": True, "strokeWidth": 2},
            "encoding": {
                "x": {"field": "date", "type": "temporal", "axis": {"labelColor": "#8fa5b8", "titleColor": "#8fa5b8", "gridColor": "#173044", "title": "Event date"}},
                "y": {"field": "Value", "type": "quantitative", "axis": {"labelColor": "#8fa5b8", "titleColor": "#8fa5b8", "gridColor": "#173044", "title": "Records"}},
                "color": {"field": "Series", "type": "nominal", "scale": {"range": ["#00c8ff", "#ff3150"]}},
                "tooltip": [{"field": "date", "type": "temporal", "title": "Date"},
                            {"field": "Series", "type": "nominal"},
                            {"field": "Value", "type": "quantitative", "title": "Records"}]
            },
            "background": "#07121c",
            "config": {"view": {"stroke": "#173247"}, "axis": {"domainColor": "#294258", "tickColor": "#294258"}}
        }
        st.vega_lite_chart(pd.DataFrame(chart_data), spec, use_container_width=True)
    else:
        st.info("No dated telemetry records available.")
    st.markdown('</div>', unsafe_allow_html=True)

    a, b = st.columns(2, gap="medium")
    with a:
        st.markdown('<div class="panel"><div class="panel-title">TABLE LOAD HEALTH</div><div class="panel-sub">ROWS LOADED PER CURATED TABLE</div>', unsafe_allow_html=True)
        health = pd.DataFrame({
            "Table": ["Battery 360", "Event Context", "RCA", "Prediction"],
            "Rows": [len(vehicles), len(events), len(rca), len(prediction)]
        })
        vega_bar(health, "Table", "Rows", horizontal=True)
        st.markdown('</div>', unsafe_allow_html=True)
    with b:
        if not dq.empty:
            st.markdown('<div class="panel"><div class="panel-title">DQ RESULTS — LATEST</div>', unsafe_allow_html=True)
            dark_table(dq.head(12))
        else:
            st.markdown('<div class="panel"><div class="panel-title">DAILY VOLUME — DETAIL</div><div class="panel-sub">RECORDS &amp; DTC EVENTS PER DAY</div>', unsafe_allow_html=True)
            dark_table(daily.tail(12), max_rows=12)
        st.markdown('</div>', unsafe_allow_html=True)

def render_rca(f_rca=None, f_prediction=None):
    _rca = f_rca if f_rca is not None else rca
    render_page_header("RCA Insights", "Root-cause patterns, environmental drivers and investigation evidence", "🎯")
    if _rca.empty:
        st.warning("VEHICLE_BATTERY_RCA returned no rows.")
        return
    sup_col = pick_col(_rca, ["SUPPLIER"])
    st.markdown('<div class="panel"><div class="panel-title">EVENTS BY SUPPLIER (RCA EVIDENCE)</div>', unsafe_allow_html=True)
    ev_col = pick_col(_rca, ["DTC_ERROR_EVENTS", "TOTAL_EVENTS"])
    if sup_col and ev_col:
        grp = _rca.groupby(sup_col)[ev_col].sum().sort_values(ascending=False).head(10).reset_index()
        grp.columns = ["Supplier", "Events"]
        vega_bar(grp, "Supplier", "Events", horizontal=True)
    else:
        st.info("No supplier / event evidence detected.")
    st.markdown('</div>', unsafe_allow_html=True)

    st.markdown('<div class="section-title">📋 RCA Evidence Detail</div>', unsafe_allow_html=True)
    st.markdown('<div class="panel"><div class="panel-title">RCA EVIDENCE</div>', unsafe_allow_html=True)
    dark_table(_rca.head(12))
    st.markdown('</div>', unsafe_allow_html=True)

def render_events(f_events=None):
    _ev = f_events if f_events is not None else events
    render_page_header("Events & Environment", "Vehicle events, weather context and environmental risk signals", "🌎")
    if _ev.empty:
        st.warning("VEHICLE_EVENT_CONTEXT returned no rows.")
        return

    # --- Weather KPI Row ---
    avg_temp = float(_ev["AVG_TEMP_F"].mean()) if "AVG_TEMP_F" in _ev.columns and not _ev["AVG_TEMP_F"].dropna().empty else None
    avg_wind = float(_ev["AVG_WIND_SPEED_MPH"].mean()) if "AVG_WIND_SPEED_MPH" in _ev.columns and not _ev["AVG_WIND_SPEED_MPH"].dropna().empty else None
    avg_precip = float(_ev["TOT_PRECIPITATION_IN"].mean()) if "TOT_PRECIPITATION_IN" in _ev.columns and not _ev["TOT_PRECIPITATION_IN"].dropna().empty else None
    avg_snow = float(_ev["TOT_SNOWFALL_IN"].mean()) if "TOT_SNOWFALL_IN" in _ev.columns and not _ev["TOT_SNOWFALL_IN"].dropna().empty else None

    w1, w2, w3, w4 = st.columns(4, gap="medium")
    with w1:
        val = f"{avg_temp:.1f}°F" if avg_temp is not None else "—"
        st.markdown(f'<div class="kpi kpi-amber"><div class="kpi-icon">🌡️</div><div class="kpi-label">AVG TEMPERATURE</div><div class="kpi-value">{val}</div><div class="kpi-foot">Across all events</div></div>', unsafe_allow_html=True)
    with w2:
        val = f"{avg_wind:.1f} mph" if avg_wind is not None else "—"
        st.markdown(f'<div class="kpi kpi-blue"><div class="kpi-icon">💨</div><div class="kpi-label">AVG WIND SPEED</div><div class="kpi-value">{val}</div><div class="kpi-foot">Mean across events</div></div>', unsafe_allow_html=True)
    with w3:
        val = f'{avg_precip:.2f}"' if avg_precip is not None else "—"
        st.markdown(f'<div class="kpi kpi-green"><div class="kpi-icon">🌧️</div><div class="kpi-label">AVG PRECIPITATION</div><div class="kpi-value">{val}</div><div class="kpi-foot">Inches per event day</div></div>', unsafe_allow_html=True)
    with w4:
        val = f'{avg_snow:.2f}"' if avg_snow is not None else "—"
        st.markdown(f'<div class="kpi kpi-purple" style="border-top:2px solid #8b5cf6"><div class="kpi-icon">❄️</div><div class="kpi-label">AVG SNOWFALL</div><div class="kpi-value">{val}</div><div class="kpi-foot">Inches per event day</div></div>', unsafe_allow_html=True)

    # --- Temperature Trend ---
    st.markdown('<div class="section-title">🌡️ Temperature & Weather Trends</div>', unsafe_allow_html=True)
    t1, t2 = st.columns(2, gap="medium")
    with t1:
        st.markdown('<div class="panel"><div class="panel-title">AVG TEMPERATURE (°F) BY EVENT DATE</div>', unsafe_allow_html=True)
        dcol = pick_col(_ev, ["EVENT_DATE", "DATE", "CREATED_AT"])
        if dcol and "AVG_TEMP_F" in _ev.columns:
            _tdf = _ev[[dcol, "AVG_TEMP_F"]].dropna().copy()
            _tdf["_D"] = pd.to_datetime(_tdf[dcol], errors="coerce")
            _tdf = _tdf.dropna(subset=["_D"]).groupby("_D").agg({"AVG_TEMP_F": "mean"}).reset_index()
            _tdf.columns = ["Date", "Avg Temp °F"]
            if not _tdf.empty:
                spec = {
                    "mark": {"type": "area", "line": {"color": "#ffad18", "strokeWidth": 2},
                             "color": {"x1": 1, "y1": 1, "x2": 1, "y2": 0, "gradient": "linear",
                                       "stops": [{"offset": 0, "color": "rgba(255,173,24,0.01)"},
                                                  {"offset": 1, "color": "rgba(255,173,24,0.20)"}]},
                             "point": {"filled": True, "size": 20, "color": "#ffad18"}},
                    "encoding": {
                        "x": {"field": "Date", "type": "temporal",
                               "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044", "format": "%b %d", "labelAngle": -30}},
                        "y": {"field": "Avg Temp °F", "type": "quantitative",
                               "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044"}},
                        "tooltip": [{"field": "Date", "type": "temporal", "format": "%b %d, %Y"},
                                    {"field": "Avg Temp °F", "type": "quantitative", "format": ".1f"}]
                    },
                    "background": "#07121c", "config": {"view": {"stroke": "#173247"}}, "height": 240
                }
                st.vega_lite_chart(_tdf, spec, use_container_width=True)
            else:
                st.info("No temperature data available.")
        else:
            st.info("Temperature column not available.")
        st.markdown('</div>', unsafe_allow_html=True)

    with t2:
        st.markdown('<div class="panel"><div class="panel-title">WIND SPEED & PRECIPITATION</div>', unsafe_allow_html=True)
        if dcol and "AVG_WIND_SPEED_MPH" in _ev.columns:
            _wdf = _ev[[dcol, "AVG_WIND_SPEED_MPH", "TOT_PRECIPITATION_IN"]].dropna(subset=[dcol]).copy()
            _wdf["_D"] = pd.to_datetime(_wdf[dcol], errors="coerce")
            _wdf = _wdf.dropna(subset=["_D"]).groupby("_D").agg({
                "AVG_WIND_SPEED_MPH": "mean", "TOT_PRECIPITATION_IN": "mean"
            }).reset_index()
            _wdf.columns = ["Date", "Wind (mph)", "Precip (in)"]
            if not _wdf.empty:
                spec = {
                    "transform": [{"fold": ["Wind (mph)", "Precip (in)"], "as": ["Metric", "Value"]}],
                    "mark": {"type": "line", "point": True, "strokeWidth": 2},
                    "encoding": {
                        "x": {"field": "Date", "type": "temporal",
                               "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044", "format": "%b %d", "labelAngle": -30}},
                        "y": {"field": "Value", "type": "quantitative",
                               "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044"}},
                        "color": {"field": "Metric", "type": "nominal",
                                   "scale": {"range": ["#00c8ff", "#18e879"]}},
                        "tooltip": [{"field": "Date", "type": "temporal", "format": "%b %d"},
                                    {"field": "Metric"}, {"field": "Value", "type": "quantitative", "format": ".2f"}]
                    },
                    "background": "#07121c", "config": {"view": {"stroke": "#173247"}}, "height": 240
                }
                st.vega_lite_chart(_wdf, spec, use_container_width=True)
            else:
                st.info("No wind/precipitation data.")
        else:
            st.info("Weather columns not available.")
        st.markdown('</div>', unsafe_allow_html=True)

    # --- Events Section ---
    st.markdown('<div class="section-title">📡 DTC Events & State Distribution</div>', unsafe_allow_html=True)
    event_col = pick_col(_ev, ["DTC_CODE", "DTC_DESCRIPTION", "EVENT_TYPE", "EVENT"])
    a, b = st.columns([.55, .45], gap="medium")
    with a:
        st.markdown('<div class="panel"><div class="panel-title">EVENT / DTC MIX</div>', unsafe_allow_html=True)
        if event_col:
            x = _ev[event_col].astype(str).replace("nan", np.nan).dropna().value_counts().head(10).reset_index()
            x.columns = ["Event", "Records"]
            vega_bar(x, "Event", "Records", horizontal=True)
        else:
            st.info("No event category column detected.")
        st.markdown('</div>', unsafe_allow_html=True)
    with b:
        st.markdown('<div class="panel"><div class="panel-title">EVENTS BY STATE — TOP 15</div>', unsafe_allow_html=True)
        scol = pick_col(_ev, ["STATE", "STATE_AB"])
        if scol:
            st_dist = _ev[scol].value_counts().head(15).reset_index()
            st_dist.columns = ["State", "Events"]
            vega_bar(st_dist, "State", "Events", horizontal=True)
        else:
            st.info("No state column detected.")
        st.markdown('</div>', unsafe_allow_html=True)

    # --- Event context table ---
    st.markdown('<div class="section-title">📋 Latest Event Context</div>', unsafe_allow_html=True)
    st.markdown('<div class="panel">', unsafe_allow_html=True)
    disp_cols = ["CAR_ID", "STATE", "EVENT_DATE", "DTC_CODE", "DTC_DESCRIPTION", "AVG_TEMP_F", "AVG_WIND_SPEED_MPH", "SUPPLIER", "BATTERY_TYPE"]
    avail = [c for c in disp_cols if c in _ev.columns]
    dark_table(_ev[avail].head(15) if avail else _ev.head(12), max_rows=15)
    st.markdown('</div>', unsafe_allow_html=True)

def render_vehicle_quality(f_vq=None):
    _vq = f_vq if f_vq is not None else qdf(f"SELECT * FROM {TABLE_VQ} LIMIT 20000")
    render_page_header("Vehicle Quality", "Quality scores, grades, risk factors, battery & environmental analysis", "🔧")
    if _vq.empty:
        st.warning("VEHICLE_QUALITY_SCORECARD returned no rows.")
        return

    # KPIs
    total = len(_vq)
    avg_score = float(_vq["QUALITY_SCORE"].mean()) if "QUALITY_SCORE" in _vq.columns else 0
    grade_a = int((_vq["QUALITY_GRADE"] == "A").sum()) if "QUALITY_GRADE" in _vq.columns else 0
    grade_f = int((_vq["QUALITY_GRADE"] == "F").sum()) if "QUALITY_GRADE" in _vq.columns else 0
    grade_d = int((_vq["QUALITY_GRADE"] == "D").sum()) if "QUALITY_GRADE" in _vq.columns else 0
    at_risk = grade_d + grade_f

    k1, k2, k3, k4 = st.columns(4, gap="medium")
    with k1:
        st.markdown(f'<div class="kpi kpi-blue"><div class="kpi-icon">🔧</div><div class="kpi-label">VEHICLES SCORED</div><div class="kpi-value">{fmt_int(total)}</div><div class="kpi-foot">Quality scorecard</div></div>', unsafe_allow_html=True)
    with k2:
        color = "kpi-green" if avg_score >= 70 else "kpi-amber" if avg_score >= 50 else "kpi-red"
        st.markdown(f'<div class="kpi {color}"><div class="kpi-icon">📊</div><div class="kpi-label">AVG QUALITY SCORE</div><div class="kpi-value">{avg_score:.1f}</div><div class="kpi-foot">Scale 0-100</div></div>', unsafe_allow_html=True)
    with k3:
        st.markdown(f'<div class="kpi kpi-green"><div class="kpi-icon">✅</div><div class="kpi-label">GRADE A (EXCELLENT)</div><div class="kpi-value">{fmt_int(grade_a)}</div><div class="kpi-foot">{grade_a*100//max(total,1)}% of fleet</div></div>', unsafe_allow_html=True)
    with k4:
        st.markdown(f'<div class="kpi kpi-red"><div class="kpi-icon">🚨</div><div class="kpi-label">AT RISK (D + F)</div><div class="kpi-value">{fmt_int(at_risk)}</div><div class="kpi-foot">{grade_d} Poor + {grade_f} Critical</div></div>', unsafe_allow_html=True)

    # Grade distribution + Battery type quality
    st.markdown('<div class="section-title">📊 Quality Grade Distribution & Battery Analysis</div>', unsafe_allow_html=True)
    a, b = st.columns(2, gap="medium")
    with a:
        st.markdown('<div class="panel"><div class="panel-title">QUALITY GRADE DISTRIBUTION</div>', unsafe_allow_html=True)
        if "QUALITY_GRADE" in _vq.columns:
            grade_order = ["A", "B", "C", "D", "F"]
            grade_colors = ["#18e879", "#00c8ff", "#ffad18", "#ff8c00", "#ff3150"]
            gc = _vq["QUALITY_GRADE"].value_counts()
            gdf = pd.DataFrame({"Grade": grade_order, "Vehicles": [int(gc.get(g, 0)) for g in grade_order]})
            spec = {
                "mark": {"type": "bar", "cornerRadiusEnd": 5},
                "encoding": {
                    "x": {"field": "Grade", "type": "nominal", "sort": grade_order,
                           "axis": {"labelColor": "#d7e3ec", "labelAngle": 0}},
                    "y": {"field": "Vehicles", "type": "quantitative",
                           "axis": {"labelColor": "#8fa5b8", "gridColor": "#173044", "format": ",d"}},
                    "color": {"field": "Grade", "type": "nominal",
                               "scale": {"domain": grade_order, "range": grade_colors}, "legend": None},
                    "tooltip": [{"field": "Grade"}, {"field": "Vehicles", "format": ","}]
                },
                "background": "#07121c", "config": {"view": {"stroke": "#173247"}}
            }
            st.vega_lite_chart(gdf, spec, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

    with b:
        st.markdown('<div class="panel"><div class="panel-title">AVG QUALITY SCORE BY BATTERY TYPE</div>', unsafe_allow_html=True)
        if "BATTERY_TYPE" in _vq.columns and "QUALITY_SCORE" in _vq.columns:
            bt = _vq.groupby("BATTERY_TYPE").agg({"QUALITY_SCORE": "mean", "CAR_ID": "count"}).reset_index()
            bt.columns = ["Battery Type", "Avg Score", "Vehicles"]
            bt["Avg Score"] = bt["Avg Score"].round(1)
            bt = bt.sort_values("Avg Score", ascending=False)
            vega_bar(bt, "Battery Type", "Avg Score", horizontal=True)
        st.markdown('</div>', unsafe_allow_html=True)

    # Supplier quality + Temperature risk
    st.markdown('<div class="section-title">🏭 Supplier Quality & Environmental Risk</div>', unsafe_allow_html=True)
    c, d = st.columns(2, gap="medium")
    with c:
        st.markdown('<div class="panel"><div class="panel-title">SUPPLIER QUALITY RANKING</div>', unsafe_allow_html=True)
        if "SUPPLIER" in _vq.columns:
            sq = _vq.groupby("SUPPLIER").agg({
                "QUALITY_SCORE": "mean", "FAILURE_PROBABILITY_PCT": "mean", "CAR_ID": "count"
            }).reset_index()
            sq.columns = ["Supplier", "Avg Score", "Avg Fail %", "Vehicles"]
            sq["Avg Score"] = sq["Avg Score"].round(1)
            sq["Avg Fail %"] = sq["Avg Fail %"].round(1)
            sq = sq.sort_values("Avg Score", ascending=False)
            dark_table(sq, max_rows=10)
        st.markdown('</div>', unsafe_allow_html=True)

    with d:
        st.markdown('<div class="panel"><div class="panel-title">BATTERY TYPE × TEMPERATURE RISK</div>', unsafe_allow_html=True)
        if "BATTERY_TYPE" in _vq.columns and "AVG_TEMP_F" in _vq.columns:
            _vqt = _vq[["BATTERY_TYPE", "AVG_TEMP_F", "FAILURE_PROBABILITY_PCT"]].dropna().copy()
            _vqt["Temp Range"] = pd.cut(_vqt["AVG_TEMP_F"], bins=[-20, 20, 32, 50, 70, 120],
                                         labels=["<20°F", "20-32°F", "32-50°F", "50-70°F", ">70°F"])
            hm = _vqt.groupby(["BATTERY_TYPE", "Temp Range"])["FAILURE_PROBABILITY_PCT"].mean().reset_index()
            hm.columns = ["Battery Type", "Temp Range", "Avg Fail %"]
            hm["Avg Fail %"] = hm["Avg Fail %"].round(1)
            if not hm.empty:
                spec = {
                    "mark": {"type": "rect", "cornerRadius": 4},
                    "encoding": {
                        "x": {"field": "Temp Range", "type": "nominal",
                               "axis": {"labelColor": "#d7e3ec", "labelAngle": 0}},
                        "y": {"field": "Battery Type", "type": "nominal",
                               "axis": {"labelColor": "#d7e3ec"}},
                        "color": {"field": "Avg Fail %", "type": "quantitative",
                                   "scale": {"range": ["#07121c", "#00c8ff", "#ffad18", "#ff3150"]}},
                        "tooltip": [{"field": "Battery Type"}, {"field": "Temp Range"},
                                    {"field": "Avg Fail %", "format": ".1f"}]
                    },
                    "background": "#07121c", "config": {"view": {"stroke": "#173247"}}, "height": 200
                }
                st.vega_lite_chart(hm, spec, use_container_width=True)
        st.markdown('</div>', unsafe_allow_html=True)

    # At-risk vehicles table
    st.markdown('<div class="section-title">🚨 At-Risk Vehicles (Grade D & F)</div>', unsafe_allow_html=True)
    st.markdown('<div class="panel">', unsafe_allow_html=True)
    if "QUALITY_GRADE" in _vq.columns:
        at_risk_df = _vq[_vq["QUALITY_GRADE"].isin(["D", "F"])].copy()
        at_risk_df = at_risk_df.sort_values("QUALITY_SCORE", ascending=True)
        disp = ["CAR_ID", "VIN", "STATE", "BATTERY_TYPE", "SUPPLIER", "QUALITY_SCORE", "QUALITY_GRADE", "FAILURE_PROBABILITY_PCT", "ERROR_RATE_PCT", "AVG_TEMP_F", "RISK_FACTORS"]
        avail = [c for c in disp if c in at_risk_df.columns]
        if not at_risk_df.empty:
            dark_table(at_risk_df[avail].head(20), max_rows=20)
        else:
            st.info("No at-risk vehicles (Grade D or F) in this selection.")
    st.markdown('</div>', unsafe_allow_html=True)

def render_ops_cost():
    render_page_header("Ops & Cost Intelligence", "Pipeline activity, layer-wise cost breakdown, storage trends and credit monitoring", "💰")

    CREDIT_PRICE = 3.00  # $/credit — adjust to your contract rate

    # Ensure warehouse is active for ACCOUNT_USAGE queries
    if session:
        try:
            session.sql(f"USE WAREHOUSE {WH}").collect()
        except Exception:
            pass

    @st.cache_data(ttl=120)
    def load_ops_direct():
        """Query ACCOUNT_USAGE views directly — no OPS Dynamic Tables needed."""
        wh = qdf("""
            SELECT WAREHOUSE_NAME, DATE_TRUNC('DAY', START_TIME) AS USAGE_DATE,
                   SUM(CREDITS_USED) AS CREDITS_USED, SUM(CREDITS_USED_COMPUTE) AS CREDITS_COMPUTE,
                   SUM(CREDITS_USED_CLOUD_SERVICES) AS CREDITS_CLOUD, COUNT(*) AS METERING_EVENTS
            FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
            WHERE START_TIME >= DATEADD(DAY, -90, CURRENT_TIMESTAMP())
            GROUP BY WAREHOUSE_NAME, DATE_TRUNC('DAY', START_TIME)
        """)
        sv = qdf("""
            SELECT TASK_NAME, DATABASE_NAME, SCHEMA_NAME,
                   DATE_TRUNC('DAY', START_TIME) AS USAGE_DATE,
                   SUM(CREDITS_USED) AS CREDITS_USED, COUNT(*) AS TASK_RUNS,
                   AVG(DATEDIFF('SECOND', START_TIME, END_TIME)) AS AVG_DURATION_SEC
            FROM SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY
            WHERE START_TIME >= DATEADD(DAY, -90, CURRENT_TIMESTAMP())
              AND DATABASE_NAME = 'AUTOPULSE_AI'
            GROUP BY TASK_NAME, DATABASE_NAME, SCHEMA_NAME, DATE_TRUNC('DAY', START_TIME)
        """)
        pp = qdf("""
            SELECT PIPE_NAME, DATE_TRUNC('DAY', START_TIME) AS USAGE_DATE,
                   SUM(CREDITS_USED) AS CREDITS_USED, SUM(BYTES_INSERTED) AS BYTES_INSERTED,
                   SUM(FILES_INSERTED) AS FILES_INSERTED
            FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
            WHERE START_TIME >= DATEADD(DAY, -90, CURRENT_TIMESTAMP())
            GROUP BY PIPE_NAME, DATE_TRUNC('DAY', START_TIME)
        """)
        storage = qdf("""
            SELECT USAGE_DATE, STORAGE_BYTES, STAGE_BYTES, FAILSAFE_BYTES,
                   ROUND(STORAGE_BYTES / POWER(1024, 4), 4) AS STORAGE_TB,
                   ROUND(STAGE_BYTES / POWER(1024, 4), 4) AS STAGE_TB,
                   ROUND(FAILSAFE_BYTES / POWER(1024, 4), 4) AS FAILSAFE_TB,
                   ROUND((STORAGE_BYTES + STAGE_BYTES + FAILSAFE_BYTES) / POWER(1024, 4), 4) AS TOTAL_TB
            FROM SNOWFLAKE.ACCOUNT_USAGE.STORAGE_USAGE
            WHERE USAGE_DATE >= DATEADD(DAY, -90, CURRENT_DATE())
        """)
        qh = qdf("""
            SELECT
                CASE
                    WHEN SCHEMA_NAME = 'RAW' THEN 'RAW'
                    WHEN SCHEMA_NAME IN ('CLEAN', 'DQ') THEN 'CLEAN'
                    WHEN SCHEMA_NAME = 'CURATED' THEN 'CURATED'
                    WHEN SCHEMA_NAME IN ('AI', 'ML', 'SEMANTIC') THEN 'AI_AGENT'
                    ELSE 'OTHER'
                END AS LAYER,
                SCHEMA_NAME,
                COUNT(*) AS QUERY_RUNS,
                SUM(CREDITS_USED_CLOUD_SERVICES) AS CREDITS
            FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
            WHERE DATABASE_NAME = 'AUTOPULSE_AI'
              AND START_TIME >= DATEADD('day', -90, CURRENT_TIMESTAMP())
              AND SCHEMA_NAME IS NOT NULL
            GROUP BY LAYER, SCHEMA_NAME
            ORDER BY CREDITS DESC
        """)
        activity = qdf("""
            SELECT NAME AS TASK_NAME, STATE, SCHEMA_NAME,
                   SCHEDULED_TIME, COMPLETED_TIME,
                   DATEDIFF('SECOND', QUERY_START_TIME, COMPLETED_TIME) AS DURATION_SEC
            FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
            WHERE DATABASE_NAME = 'AUTOPULSE_AI'
              AND SCHEDULED_TIME >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())
            ORDER BY SCHEDULED_TIME DESC
            LIMIT 500
        """)
        return wh, sv, pp, storage, qh, activity

    try:
        wh, sv, pp, storage, query_hist, activity = load_ops_direct()
    except Exception as e:
        st.warning(f"OPS data not available yet: {e}")
        return

    # --- KPI Row ---
    total_wh_credits = float(wh["CREDITS_USED"].sum()) if not wh.empty else 0
    total_task_credits = float(sv["CREDITS_USED"].sum()) if not sv.empty else 0
    total_pipe_credits = float(pp["CREDITS_USED"].sum()) if not pp.empty else 0
    total_credits = total_wh_credits + total_task_credits + total_pipe_credits
    total_cost = total_credits * CREDIT_PRICE
    latest_storage = float(storage["TOTAL_TB"].iloc[-1]) if not storage.empty else 0
    storage_cost = latest_storage * 23.0
    total_task_runs = int(activity[activity["STATE"] == "SUCCEEDED"].shape[0]) if not activity.empty and "STATE" in activity.columns else 0
    total_skipped = int(activity[activity["STATE"] == "SKIPPED"].shape[0]) if not activity.empty and "STATE" in activity.columns else 0

    k1, k2, k3, k4 = st.columns(4)
    with k1:
        st.markdown(f'''<div class="kpi kpi-blue"><div class="kpi-icon">💳</div><div class="kpi-label">TOTAL COST (90d)</div><div class="kpi-value">${total_cost:,.2f}</div><div class="kpi-foot">{total_credits:,.4f} credits × ${CREDIT_PRICE:.0f}/credit</div></div>''', unsafe_allow_html=True)
    with k2:
        st.markdown(f'''<div class="kpi kpi-green"><div class="kpi-icon">💾</div><div class="kpi-label">STORAGE</div><div class="kpi-value">{latest_storage:,.4f} TB</div><div class="kpi-foot">~${storage_cost:,.2f}/mo</div></div>''', unsafe_allow_html=True)
    with k3:
        st.markdown(f'''<div class="kpi kpi-amber"><div class="kpi-icon">⚡</div><div class="kpi-label">TASK RUNS (30d)</div><div class="kpi-value">{total_task_runs:,}</div><div class="kpi-foot">{total_skipped:,} skipped (no data)</div></div>''', unsafe_allow_html=True)
    with k4:
        task_credit_pct = (total_task_credits / total_credits * 100) if total_credits > 0 else 0
        st.markdown(f'''<div class="kpi kpi-red"><div class="kpi-icon">🔥</div><div class="kpi-label">SERVERLESS CREDITS</div><div class="kpi-value">${total_task_credits * CREDIT_PRICE:,.2f}</div><div class="kpi-foot">{total_task_credits:,.4f} credits ({task_credit_pct:.1f}%)</div></div>''', unsafe_allow_html=True)

    st.markdown('<div class="section-title">📊 Layer-Wise Cost Breakdown (4 Layers)</div>', unsafe_allow_html=True)
    a, b = st.columns([.55, .45], gap="medium")

    with a:
        st.markdown('<div class="panel"><div class="panel-title">COST BY LAYER ($) — RAW / CLEAN / CURATED / AI_AGENT</div>', unsafe_allow_html=True)
        # Serverless task credits by schema
        raw_sv = float(sv[sv["SCHEMA_NAME"] == "RAW"]["CREDITS_USED"].sum()) if not sv.empty and "SCHEMA_NAME" in sv.columns else 0
        clean_sv = float(sv[sv["SCHEMA_NAME"].isin(["CLEAN", "DQ"])]["CREDITS_USED"].sum()) if not sv.empty and "SCHEMA_NAME" in sv.columns else 0
        curated_sv = float(sv[sv["SCHEMA_NAME"] == "CURATED"]["CREDITS_USED"].sum()) if not sv.empty and "SCHEMA_NAME" in sv.columns else 0
        ai_sv = float(sv[sv["SCHEMA_NAME"].isin(["AI", "ML", "SEMANTIC"])]["CREDITS_USED"].sum()) if not sv.empty and "SCHEMA_NAME" in sv.columns else 0

        raw_credits = total_pipe_credits + raw_sv
        clean_credits = clean_sv
        curated_credits = curated_sv
        ai_agent_credits = ai_sv

        # Add query history credits per layer
        if not query_hist.empty and "LAYER" in query_hist.columns:
            qh_agg = query_hist.groupby("LAYER").agg({"CREDITS": "sum", "QUERY_RUNS": "sum"}).to_dict("index")
            raw_credits += qh_agg.get("RAW", {}).get("CREDITS", 0)
            clean_credits += qh_agg.get("CLEAN", {}).get("CREDITS", 0)
            curated_credits += qh_agg.get("CURATED", {}).get("CREDITS", 0)
            ai_agent_credits += qh_agg.get("AI_AGENT", {}).get("CREDITS", 0)
            raw_runs = int(qh_agg.get("RAW", {}).get("QUERY_RUNS", 0))
            clean_runs = int(qh_agg.get("CLEAN", {}).get("QUERY_RUNS", 0))
            curated_runs = int(qh_agg.get("CURATED", {}).get("QUERY_RUNS", 0))
            ai_runs = int(qh_agg.get("AI_AGENT", {}).get("QUERY_RUNS", 0))
        else:
            raw_runs = clean_runs = curated_runs = ai_runs = 0

        layer_data = pd.DataFrame({
            "Layer": ["RAW", "CLEAN", "CURATED", "AI_AGENT"],
            "Credits": [raw_credits, clean_credits, curated_credits, ai_agent_credits],
            "Cost ($)": [raw_credits * CREDIT_PRICE, clean_credits * CREDIT_PRICE,
                         curated_credits * CREDIT_PRICE, ai_agent_credits * CREDIT_PRICE],
            "Query Runs": [raw_runs, clean_runs, curated_runs, ai_runs],
        })
        if layer_data["Credits"].sum() > 0:
            vega_bar(layer_data, "Layer", "Cost ($)", horizontal=True,
                     color_range=("#00c8ff", "#18e879", "#ffad18", "#8b5cf6"))
            st.markdown('<div style="margin-top:10px;">', unsafe_allow_html=True)
            dark_table(layer_data[["Layer", "Cost ($)", "Credits", "Query Runs"]], max_rows=4)
            st.markdown('</div>', unsafe_allow_html=True)
        else:
            st.info("No credit usage data available yet. Data appears after ~2h in ACCOUNT_USAGE.")
        st.markdown('</div>', unsafe_allow_html=True)

    with b:
        st.markdown('<div class="panel"><div class="panel-title">STORAGE TREND (90 DAYS)</div>', unsafe_allow_html=True)
        if not storage.empty:
            stg = storage[["USAGE_DATE", "TOTAL_TB"]].copy()
            stg.columns = ["Date", "Total TB"]
            vega_line(stg, "Date", "Total TB")
        else:
            st.info("Storage data not yet available.")
        st.markdown('</div>', unsafe_allow_html=True)

    st.markdown('<div class="section-title">🔍 Cost Details & Pipeline Activity</div>', unsafe_allow_html=True)
    c, d = st.columns([.50, .50], gap="medium")

    with c:
        st.markdown('<div class="panel"><div class="panel-title">TOP COST CONSUMERS</div>', unsafe_allow_html=True)
        if not sv.empty:
            top = sv.groupby("TASK_NAME").agg({"CREDITS_USED": "sum", "TASK_RUNS": "sum"}).reset_index()
            top.columns = ["Task", "Credits", "Runs"]
            top["Cost ($)"] = top["Credits"] * CREDIT_PRICE
            top = top.sort_values("Cost ($)", ascending=False).head(12)
            dark_table(top[["Task", "Cost ($)", "Credits", "Runs"]], max_rows=12)
        elif not wh.empty:
            wh_disp = wh.copy()
            if "CREDITS_USED" in wh_disp.columns:
                wh_disp["Cost ($)"] = wh_disp["CREDITS_USED"] * CREDIT_PRICE
            dark_table(wh_disp.head(10))
        else:
            st.info("Cost data populates after ACCOUNT_USAGE latency (~2h).")
        st.markdown('</div>', unsafe_allow_html=True)

    with d:
        st.markdown('<div class="panel"><div class="panel-title">RECENT PIPELINE RUNS</div>', unsafe_allow_html=True)
        if not activity.empty:
            recent = activity.head(15)
            display_cols = ["TASK_NAME", "STATE", "DURATION_SEC", "SCHEMA_NAME"]
            avail = [c for c in display_cols if c in recent.columns]
            dark_table(recent[avail], max_rows=15)
        else:
            st.info("Pipeline activity data not yet available.")
        st.markdown('</div>', unsafe_allow_html=True)

    # Pipe usage
    if not pp.empty:
        st.markdown('<div class="section-title">🔧 Snowpipe Usage</div>', unsafe_allow_html=True)
        e, f = st.columns([.50, .50], gap="medium")
        with e:
            st.markdown('<div class="panel"><div class="panel-title">PIPE CREDITS</div>', unsafe_allow_html=True)
            pipe_agg = pp.groupby("PIPE_NAME").agg({"CREDITS_USED": "sum", "FILES_INSERTED": "sum"}).reset_index()
            pipe_agg.columns = ["Pipe", "Credits", "Files"]
            pipe_agg["Cost ($)"] = pipe_agg["Credits"] * CREDIT_PRICE
            pipe_agg = pipe_agg.sort_values("Cost ($)", ascending=False)
            vega_bar(pipe_agg, "Pipe", "Credits", horizontal=True)
            st.markdown('</div>', unsafe_allow_html=True)
        with f:
            st.markdown('<div class="panel"><div class="panel-title">PIPE DETAILS</div>', unsafe_allow_html=True)
            dark_table(pipe_agg, max_rows=12)
            st.markdown('</div>', unsafe_allow_html=True)

# -----------------------------
# TOP HEADER / LIVE WAVE
# -----------------------------
now = datetime.now().strftime("%H:%M:%S")
st.markdown(f"""
<div class="ap-top">
  <div class="ap-brand">
    <div class="ap-logo">⚡</div>
    <div>
      <div class="ap-title">AUTOPULSE <span>AI</span></div>
      <div class="ap-sub">AI-POWERED BATTERY RISK INTELLIGENCE • LIVE SNOWFLAKE ANALYTICS</div>
    </div>
    <div class="live"><span class="live-dot"></span> LIVE DATA STREAM <span style="color:#18e879">〰〰〰</span></div>
    <div class="ap-time">{now}</div>
  </div>
  <div class="live-signal"><span></span></div>
  <div class="wave">
    <svg viewBox="0 0 1200 80" preserveAspectRatio="none">
      <path d="M0,48 C90,5 160,75 250,38 S410,3 500,42 S670,76 760,35 S930,4 1020,42 S1130,70 1200,34" fill="none" stroke="#007cff" stroke-width="2"/>
      <path d="M0,60 C100,20 175,70 270,46 S430,12 525,50 S690,72 780,44 S950,15 1040,50 S1130,75 1200,45" fill="none" stroke="#8b5cf6" stroke-width="1.5"/>
      <path d="M0,28 C90,65 160,0 250,28 S410,65 500,27 S670,0 760,29 S930,62 1020,28 S1130,3 1200,30" fill="none" stroke="#13d9ff" stroke-width="1"/>
    </svg>
  </div>
</div>
""", unsafe_allow_html=True)

# -----------------------------
# LEFT AI COMMAND CENTER + MAIN DASHBOARD
# -----------------------------
rail, main = st.columns([0.31, 0.69], gap="medium")

with rail:
    if "active_page" not in st.session_state:
        st.session_state.active_page = "Executive Overview"
    if "agent_choice" not in st.session_state:
        st.session_state.agent_choice = "Battery Risk Agent"
    if "chat" not in st.session_state:
        st.session_state.chat = []

    with st.container(border=True):
        st.markdown(
            '<div class="assistant-title">🤖 AI ASSISTANT <span>LIVE</span></div>'
            '<div class="assistant-sub">Choose intelligence • ask • investigate • act</div>',
            unsafe_allow_html=True)

        agent_defs = [
            ("Battery Risk Agent", "🔋", "Risk • Prediction • RCA • Events"),
            ("Data Quality Agent", "🛡️", "DQ • Rules • Quality • Monitoring"),
            ("RCA Agent", "🎯", "Root cause • Investigation"),
            ("Vehicle Quality Agent", "🔧", "Scores • Grades • Risk factors • Battery"),
            ("Ops & Cost Agent", "💰", "Cost • Pipeline • Storage • Credits"),
        ]
        AGENT_TO_PAGE = {
            "Battery Risk Agent": "Risk & Prediction",
            "Data Quality Agent": "Data Quality",
            "RCA Agent": "RCA Insights",
            "Vehicle Quality Agent": "Vehicle Quality",
            "Ops & Cost Agent": "Ops & Cost Intelligence",
        }
        st.markdown('<div class="rail-label">SELECT INTELLIGENCE</div>', unsafe_allow_html=True)
        for label, icon, desc in agent_defs:
            active = st.session_state.agent_choice == label
            if st.button(f"{icon}  {label}", key="agent_btn_" + label, use_container_width=True,
                         type="primary" if active else "secondary"):
                st.session_state.agent_choice = label
                st.session_state.active_page = AGENT_TO_PAGE.get(label, st.session_state.active_page)
                st.rerun()
            st.markdown(f'<div class="agent-description">{desc}</div>', unsafe_allow_html=True)

        agent_map = {
            "Battery Risk Agent": resolve_agent(BATTERY_AGENT, ("BATTERY", "RISK")),
            "Data Quality Agent": resolve_agent(DQ_AGENT, ("DQ", "QUALITY")),
            "RCA Agent": resolve_agent(RCA_AGENT, ("RCA", "ROOT", "CAUSE")),
            "Vehicle Quality Agent": resolve_agent(VQ_AGENT, ("VEHICLE", "QUALITY", "SCORE")),
            "Ops & Cost Agent": resolve_agent(OPS_AGENT, ("OPS", "COST", "CREDIT")),
        }
        selected_agent = agent_map[st.session_state.agent_choice]
        st.markdown(f'<div class="connected-agent">● CONNECTED<br><span>{selected_agent}</span></div>', unsafe_allow_html=True)

        st.markdown('<div class="rail-label">SUGGESTED QUESTIONS</div>', unsafe_allow_html=True)
        agent_suggestions = {
            "Battery Risk Agent": [
                "How many vehicles are medium risk?",
                "Which vehicles have the highest failure probability?",
                "Which suppliers carry the most risk?",
                "How many vehicles are predicted to fail in the next 30 days?",
            ],
            "Data Quality Agent": [
                "What is the overall DQ pass rate across all tables?",
                "Which tables have the most DQ failures?",
                "Show me DQ trends for the last 7 days",
                "Which DQ rules are failing most frequently?",
            ],
            "RCA Agent": [
                "What are the top root causes of battery failure?",
                "Which battery components fail most often?",
                "Show root cause breakdown by supplier",
                "Which vehicle models have the most RCA entries?",
            ],
            "Vehicle Quality Agent": [
                "Show quality grade distribution by battery type",
                "Which suppliers have the worst quality scores?",
                "Which battery type at cold temperatures has the highest failure rate?",
                "List all Grade F vehicles with their risk factors",
            ],
            "Ops & Cost Agent": [
                "What is the total warehouse credit usage this month?",
                "Show me layer-wise cost breakdown for Raw, Clean, and Curated",
                "Which tasks consume the most credits?",
                "What is the current storage cost trend?",
            ],
        }
        suggested = agent_suggestions.get(st.session_state.agent_choice, agent_suggestions["Battery Risk Agent"])
        for i, prompt in enumerate(suggested):
            if st.button(prompt, key=f"suggest_{i}", use_container_width=True):
                st.session_state.pending_question = prompt
                st.rerun()

        st.markdown('<div class="rail-label chat-label">AGENT CHAT</div>', unsafe_allow_html=True)

        pending = st.session_state.pop("pending_question", None)
        chat_cols = st.columns([0.84, 0.16], gap="small")
        with chat_cols[0]:
            typed = st.text_input("Ask", value="", placeholder="Ask AutoPulse AI…",
                                  label_visibility="collapsed", key="ap_text_input")
        with chat_cols[1]:
            send = st.button("➤", key="ap_send", use_container_width=True)

        question = typed.strip() if typed else ""
        if pending:
            question = pending
        if question and (send or pending):
            st.session_state.chat.append(("user", question))
            with st.spinner(f"Querying {st.session_state.agent_choice}…"):
                answer, ok = run_cortex_agent(selected_agent, question)
            st.session_state.chat.append(("assistant", answer))
            st.rerun()

        if not st.session_state.chat:
            st.markdown('<div class="chat-empty"><div class="chat-meta">AUTOPULSE AI • READY</div>'
                        '<div class="chat-main">Ask about battery risk, DQ, predictions, RCA, events or environment.</div></div>',
                        unsafe_allow_html=True)
        else:
            recent = st.session_state.chat[-6:]
            pairs = [(recent[i], recent[i+1]) for i in range(0, len(recent) - 1, 2)]
            if len(recent) % 2 == 1:
                pairs.append((recent[-1],))
            for pair in reversed(pairs):
                for role, msg in pair:
                    cls = "chat-user-final" if role == "user" else "chat-ai-final"
                    label = "YOU" if role == "user" else "AUTOPULSE AI • CORTEX"
                    safe = (str(msg).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\n", "<br>"))
                    st.markdown(f'<div class="{cls}"><div class="chat-meta">{label}</div>{safe}</div>', unsafe_allow_html=True)

        st.markdown('<div class="agent-status-strip"><span class="live-dot"></span> Cortex Intelligence Online</div>', unsafe_allow_html=True)

    with st.container(border=True):
        st.markdown('<div class="rail-label">DASHBOARD MODULES</div>', unsafe_allow_html=True)
        page_defs = [
            ("Executive Overview", "🏠"),
            ("Risk & Prediction", "📈"),
            ("Vehicle Quality", "🔧"),
            ("Data Quality", "🛡️"),
            ("RCA Insights", "🎯"),
            ("Events & Environment", "🌎"),
            ("Ops & Cost Intelligence", "💰"),
        ]
        for page, icon in page_defs:
            if st.button(f"{icon}  {page}", key="page_" + page, use_container_width=True,
                         type="primary" if st.session_state.active_page == page else "secondary"):
                st.session_state.active_page = page
                st.rerun()

with main:
    active_page = st.session_state.get("active_page", "Executive Overview")

    # Show state filter only on pages that support it (not DQ, not Ops)
    _no_state_pages = {"Data Quality", "Ops & Cost Intelligence"}
    if active_page not in _no_state_pages:
        _fc1, _fc2, _fc3 = st.columns([0.25, 0.55, 0.20])
        with _fc1:
            st.session_state.state_filter = st.selectbox(
                "🌎 State Drill-Down", ["All States"] + ALL_STATES,
                index=0 if st.session_state.state_filter == "All States"
                else (["All States"] + ALL_STATES).index(st.session_state.state_filter)
                if st.session_state.state_filter in ALL_STATES else 0,
                key="state_select_main")
        with _fc2:
            if st.session_state.state_filter != "All States":
                st.markdown(f'<div style="padding:8px 0;color:#00c8ff;font-size:13px;font-weight:700;">Filtered: {st.session_state.state_filter}</div>', unsafe_allow_html=True)
        with _fc3:
            if active_page != "Executive Overview":
                st.markdown('<div style="height:8px"></div>', unsafe_allow_html=True)
                if st.button("🏠  Home", key="home_btn", use_container_width=True):
                    st.session_state.active_page = "Executive Overview"
                    st.rerun()
    else:
        if active_page != "Executive Overview":
            _hx1, _hx2 = st.columns([0.80, 0.20])
            with _hx2:
                if st.button("🏠  Home", key="home_btn_alt", use_container_width=True):
                    st.session_state.active_page = "Executive Overview"
                    st.rerun()

    # Apply state filter to all datasets
    f_vehicles = apply_state_filter(vehicles)
    f_prediction = apply_state_filter(prediction)
    f_rca = apply_state_filter(rca)
    f_events = apply_state_filter(events)

    if active_page != "Executive Overview":
        if active_page == "Risk & Prediction":
            render_risk_prediction(f_vehicles, f_prediction, f_rca, f_events)
        elif active_page == "Data Quality":
            render_dq()
        elif active_page == "RCA Insights":
            render_rca(f_rca, f_prediction)
        elif active_page == "Vehicle Quality":
            vq_data = qdf(f"SELECT * FROM {TABLE_VQ} LIMIT 20000")
            f_vq = apply_state_filter(vq_data)
            render_vehicle_quality(f_vq)
        elif active_page == "Events & Environment":
            render_events(f_events)
        elif active_page == "Ops & Cost Intelligence":
            render_ops_cost()
        st.markdown('<div class="footer">⚡ AutoPulse AI • Snowflake Cortex • Live governed battery intelligence</div>', unsafe_allow_html=True)
        st.stop()

    st.markdown("""
    <div class="status">
      <div class="status-item"><span class="status-icon">〽</span> Data Pipeline <b>LIVE</b></div>
      <div class="status-item"><span class="status-icon">🔋</span> Battery 360 <b>LIVE</b></div>
      <div class="status-item"><span class="status-icon">📈</span> Predictions <b>LIVE</b></div>
      <div class="status-item"><span class="status-icon">🛡️</span> DQ Monitoring <b>LIVE</b></div>
      <div class="status-item"><span class="status-icon">🧠</span> Cortex Agents <b>ONLINE</b></div>
    </div>
    """, unsafe_allow_html=True)

    # KPIs — recomputed from filtered data
    _fv_id = pick_col(f_vehicles, ["CAR_ID", "VEHICLE_ID", "VIN", "VEHICLE_KEY"])
    _f_total_vehicles = int(f_vehicles[_fv_id].nunique()) if _fv_id and not f_vehicles.empty else len(f_vehicles)
    _fp_id = pick_col(f_prediction, ["CAR_ID", "VEHICLE_ID", "VIN"])
    _f_scored = int(f_prediction[_fp_id].nunique()) if _fp_id and not f_prediction.empty else len(f_prediction)
    _f_rc = risk_counts(f_prediction)
    _f_critical_lvl, _f_high_lvl, _f_medium, _f_low = _f_rc["CRITICAL"], _f_rc["HIGH"], _f_rc["MEDIUM"], _f_rc["LOW"]
    _f_prob = prob_pct_series(f_prediction)
    _f_max_prob = float(_f_prob.max()) if not _f_prob.empty else 0.0
    _f_avg_prob = float(_f_prob.mean()) if not _f_prob.empty else 0.0
    _f_watchlist = int((_f_prob >= WATCH_THRESHOLD).sum())
    _f_coverage = (_f_scored / max(_f_total_vehicles, 1)) * 100

    k1, k2, k3, k4 = st.columns(4, gap="medium")
    with k1:
        st.markdown(f'<div class="kpi kpi-blue"><div class="kpi-icon">🚘</div><div class="kpi-label">TOTAL VEHICLES</div><div class="kpi-value">{fmt_int(_f_total_vehicles)}</div><div class="kpi-foot">{fmt_int(_f_scored)} scored ({_f_coverage:.0f}% coverage)</div></div>', unsafe_allow_html=True)
    with k2:
        st.markdown(f'<div class="kpi kpi-amber"><div class="kpi-icon">⚠️</div><div class="kpi-label">MEDIUM RISK</div><div class="kpi-value">{fmt_int(_f_medium)}</div><div class="kpi-foot">Highest risk level present</div></div>', unsafe_allow_html=True)
    with k3:
        st.markdown(f'<div class="kpi kpi-red"><div class="kpi-icon">🔎</div><div class="kpi-label">WATCHLIST (≥{WATCH_THRESHOLD}%)</div><div class="kpi-value">{fmt_int(_f_watchlist)}</div><div class="kpi-foot">Vehicles above risk threshold</div></div>', unsafe_allow_html=True)
    with k4:
        st.markdown(f'<div class="kpi kpi-green"><div class="kpi-icon">🔋</div><div class="kpi-label">MAX FAILURE PROB</div><div class="kpi-value">{_f_max_prob:.0f}%</div><div class="kpi-foot">Fleet avg {_f_avg_prob:.2f}%</div></div>', unsafe_allow_html=True)

    c1, c2, c3, c4 = st.columns([0.25, 0.35, 0.22, 0.18], gap="medium")

    with c1:
        st.markdown('<div class="panel"><div class="panel-title">RISK DISTRIBUTION</div><div class="panel-sub">LATEST CURATED PREDICTIONS</div>', unsafe_allow_html=True)
        vals = [int(_f_critical_lvl), int(_f_high_lvl), int(_f_medium), int(_f_low)]
        total_risk = max(sum(vals), 1)
        critical_pct = vals[0] / total_risk * 100
        high_pct = vals[1] / total_risk * 100
        medium_pct = vals[2] / total_risk * 100
        st.markdown(f"""
        <div style="display:flex;align-items:center;gap:18px;padding:10px 4px 14px;">
          <div style="width:142px;height:142px;border-radius:50%;background:conic-gradient(#ff3150 0% {critical_pct}%, #ffad18 {critical_pct}% {critical_pct+high_pct}%, #f5d84e {critical_pct+high_pct}% {critical_pct+high_pct+medium_pct}%, #18e879 {critical_pct+high_pct+medium_pct}% 100%);position:relative;flex:0 0 auto;box-shadow:0 0 24px rgba(0,168,255,.12);">
            <div style="position:absolute;inset:27px;border-radius:50%;background:#07111b;display:flex;flex-direction:column;align-items:center;justify-content:center;">
              <div style="font-size:25px;font-weight:900;color:#f5f9ff;">{total_risk:,}</div>
              <div style="font-size:9px;color:#8fa5b8;letter-spacing:1px;">PREDICTIONS</div>
            </div>
          </div>
          <div style="font-size:12px;line-height:2;color:#dce8f2;">
            <div>🔴 Critical <b>{vals[0]:,}</b></div>
            <div>🟠 High <b>{vals[1]:,}</b></div>
            <div>🟡 Medium <b>{vals[2]:,}</b></div>
            <div>🟢 Low <b>{vals[3]:,}</b></div>
          </div>
        </div>
        """, unsafe_allow_html=True)
        st.markdown('</div>', unsafe_allow_html=True)

    with c2:
        st.markdown('<div class="panel"><div class="panel-title">DTC ACTIVITY TREND — LAST 30 DAYS</div><div class="panel-sub">LIVE EVENT SIGNAL (VEHICLE_EVENT_CONTEXT)</div>', unsafe_allow_html=True)
        _dcol = pick_col(f_events, ["EVENT_DATE", "DATE", "CREATED_AT"])
        if _dcol and not f_events.empty:
            _et = f_events.copy()
            _et["_D"] = pd.to_datetime(_et[_dcol], errors="coerce").dt.date
            _et = _et.dropna(subset=["_D"]).groupby("_D").size().reset_index(name="EVENTS").tail(30)
        else:
            _et = pd.DataFrame()
        if not _et.empty:
            chart_data = [{"date": str(r["_D"]), "events": int(r["EVENTS"])} for _, r in _et.iterrows()]
            spec = {
                "mark": {"type": "line", "point": True, "strokeWidth": 3},
                "encoding": {
                    "x": {"field": "date", "type": "temporal", "axis": {"labelColor": "#8fa5b8", "titleColor": "#8fa5b8", "gridColor": "#173044"}},
                    "y": {"field": "events", "type": "quantitative", "axis": {"labelColor": "#8fa5b8", "titleColor": "#8fa5b8", "gridColor": "#173044"}},
                    "color": {"value": "#00c8ff"},
                    "tooltip": [{"field": "date", "type": "temporal", "title": "Date"},
                                {"field": "events", "type": "quantitative", "title": "DTC events"}]
                },
                "background": "#07121c",
                "config": {"view": {"stroke": "#173247"}, "axis": {"domainColor": "#294258", "tickColor": "#294258"}}
            }
            st.vega_lite_chart(pd.DataFrame(chart_data), spec, use_container_width=True)
        else:
            st.info("No dated event records available yet.")
        st.markdown('</div>', unsafe_allow_html=True)

    with c3:
        st.markdown('<div class="panel"><div class="panel-title">FAILURE PROBABILITY</div><div class="panel-sub">TOP CURRENT PREDICTION SIGNALS</div>', unsafe_allow_html=True)
        vals_series = _f_prob.sort_values(ascending=False).head(12)
        if not vals_series.empty:
            chart_data = [{"vehicle": str(i + 1), "probability": float(v)} for i, v in enumerate(vals_series.reset_index(drop=True))]
            spec = {
                "mark": {"type": "bar", "cornerRadiusTopLeft": 4, "cornerRadiusTopRight": 4},
                "encoding": {
                    "x": {"field": "vehicle", "type": "ordinal", "axis": {"labelColor": "#8fa5b8", "title": None, "grid": False}},
                    "y": {"field": "probability", "type": "quantitative", "axis": {"labelColor": "#8fa5b8", "titleColor": "#8fa5b8", "gridColor": "#173044"}},
                    "color": {"field": "probability", "type": "quantitative", "scale": {"range": ["#00a8ff", "#8b5cf6", "#ffad18", "#ff3150"]}},
                    "tooltip": [{"field": "probability", "type": "quantitative", "title": "Failure %", "format": ".1f"}]
                },
                "background": "#07121c",
                "config": {"view": {"stroke": "#173247"}, "axis": {"domainColor": "#294258", "tickColor": "#294258"}}
            }
            st.vega_lite_chart(pd.DataFrame(chart_data), spec, use_container_width=True)
        else:
            st.info("No failure probability values available.")
        st.markdown('</div>', unsafe_allow_html=True)

    with c4:
        # Thermometer gauge for avg temperature
        _temp_col = "AVG_TEMP_F" if "AVG_TEMP_F" in f_events.columns else None
        _avg_t = float(f_events[_temp_col].dropna().mean()) if _temp_col and not f_events.empty and not f_events[_temp_col].dropna().empty else None
        _min_t = float(f_events[_temp_col].dropna().min()) if _avg_t is not None else None
        _max_t = float(f_events[_temp_col].dropna().max()) if _avg_t is not None else None
        _state_label = st.session_state.state_filter if st.session_state.state_filter != "All States" else "Fleet-Wide"

        st.markdown(f'<div class="panel"><div class="panel-title">🌡️ AVG TEMPERATURE</div><div class="panel-sub">{_state_label}</div>', unsafe_allow_html=True)
        if _avg_t is not None:
            # Map temp to color: cold(<32)=blue, cool(32-50)=cyan, mild(50-70)=green, warm(70-85)=orange, hot(>85)=red
            if _avg_t < 32:
                _tcolor, _tlabel = "#00a8ff", "Cold"
            elif _avg_t < 50:
                _tcolor, _tlabel = "#13d9ff", "Cool"
            elif _avg_t < 70:
                _tcolor, _tlabel = "#18e879", "Normal"
            elif _avg_t < 85:
                _tcolor, _tlabel = "#ffad18", "Warm"
            else:
                _tcolor, _tlabel = "#ff3150", "Hot"
            # Fill % for thermometer (range -20 to 120°F)
            _fill_pct = max(0, min(100, (_avg_t + 20) / 140 * 100))
            st.markdown(f"""
            <div style="display:flex;flex-direction:column;align-items:center;padding:8px 0;">
              <div style="position:relative;width:36px;height:160px;margin-bottom:8px;">
                <!-- Tube -->
                <div style="position:absolute;left:10px;top:0;width:16px;height:140px;border-radius:8px 8px 0 0;background:#102435;border:1px solid #294258;overflow:hidden;">
                  <div style="position:absolute;bottom:0;width:100%;height:{_fill_pct}%;background:linear-gradient(to top, {_tcolor}, {_tcolor}88);border-radius:6px 6px 0 0;transition:height .5s;"></div>
                </div>
                <!-- Bulb -->
                <div style="position:absolute;left:2px;top:132px;width:32px;height:32px;border-radius:50%;background:{_tcolor};border:2px solid {_tcolor}88;box-shadow:0 0 14px {_tcolor}55;"></div>
                <!-- Scale labels -->
                <div style="position:absolute;left:40px;top:-2px;font-size:8px;color:#8fa5b8;">120°F</div>
                <div style="position:absolute;left:40px;top:33px;font-size:8px;color:#8fa5b8;">80°F</div>
                <div style="position:absolute;left:40px;top:68px;font-size:8px;color:#8fa5b8;">40°F</div>
                <div style="position:absolute;left:40px;top:103px;font-size:8px;color:#8fa5b8;">0°F</div>
                <div style="position:absolute;left:40px;top:130px;font-size:8px;color:#8fa5b8;">-20°F</div>
              </div>
              <div style="font-size:28px;font-weight:900;color:{_tcolor};">{_avg_t:.1f}°F</div>
              <div style="font-size:11px;color:{_tcolor};font-weight:700;margin-top:2px;">{_tlabel}</div>
              <div style="font-size:9px;color:#71899c;margin-top:6px;">Min {_min_t:.1f}°F &nbsp;|&nbsp; Max {_max_t:.1f}°F</div>
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown('<div style="padding:40px 0;text-align:center;color:#71899c;font-size:11px;">No temperature data</div>', unsafe_allow_html=True)
        st.markdown('</div>', unsafe_allow_html=True)

    # Attention table + supplier risk
    st.markdown('<div class="section-title">🚘 Top Vehicles Requiring Attention</div>', unsafe_allow_html=True)
    a, b = st.columns([0.66, 0.34], gap="medium")
    with a:
        st.markdown('<div class="panel">', unsafe_allow_html=True)
        st.caption("Ranked by failure probability. A 100% error rate on 1 event is small-sample noise, not a failure.")
        dark_table(build_watchlist(6, f_pred=f_prediction, f_rca=f_rca), max_rows=6)
        st.markdown('</div>', unsafe_allow_html=True)
    with b:
        st.markdown('<div class="panel"><div class="panel-title">RISK BY SUPPLIER — TOP 5</div><div class="panel-sub">AVG FAILURE PROBABILITY</div>', unsafe_allow_html=True)
        sup_col = pick_col(f_rca, ["SUPPLIER"])
        rca_id = pick_col(f_rca, ["CAR_ID", "VEHICLE_ID"])
        pcol = pick_col(f_prediction, PROB_CANDS)
        pid = pick_col(f_prediction, ["CAR_ID", "VEHICLE_ID"])
        if sup_col and rca_id and pcol and pid:
            pr = f_prediction[[pid, pcol]].copy()
            pr["_P"] = pd.to_numeric(pr[pcol], errors="coerce").fillna(0)
            if pr["_P"].max() <= 1.0:
                pr["_P"] *= 100
            sup = f_rca[[rca_id, sup_col]].drop_duplicates(subset=[rca_id])
            merged = pr.merge(sup, left_on=pid, right_on=rca_id, how="left")
            grp = merged.groupby(sup_col)["_P"].mean().sort_values(ascending=False).head(5).reset_index()
            grp.columns = ["Supplier", "Avg %"]
            if not grp.empty:
                vega_bar(grp, "Supplier", "Avg %", horizontal=True)
            else:
                st.info("No supplier risk data.")
        else:
            st.info("Supplier or probability field not detected.")
        st.markdown('</div>', unsafe_allow_html=True)

    st.markdown('<div class="footer">⚡ AutoPulse AI • Snowflake Cortex • Governed Battery Risk Intelligence • Dashboard refreshes every 60 seconds</div>', unsafe_allow_html=True)

# -----------------------------
# DIAGNOSTICS
# -----------------------------
with st.expander("⚙️ Dashboard diagnostics", expanded=False):
    _diag_sel = st.session_state.state_filter
    _diag_fp = apply_state_filter(prediction)
    _diag_fr = apply_state_filter(rca)
    _diag_has_state_col = pick_col(prediction, ["STATE", "STATE_AB"])
    _diag_has_carid = pick_col(prediction, ["CAR_ID", "VEHICLE_ID", "VIN"])
    _diag_join_rows = len(_vehicle_state_df)
    st.write({
        "state_filter": _diag_sel,
        "prediction_state_col": _diag_has_state_col,
        "prediction_carid_col": _diag_has_carid,
        "vehicle_state_join_rows": _diag_join_rows,
        "vehicles_rows": len(vehicles),
        "vehicles_filtered": len(apply_state_filter(vehicles)),
        "prediction_rows": len(prediction),
        "prediction_filtered": len(_diag_fp),
        "rca_rows": len(rca),
        "rca_filtered": len(_diag_fr),
        "event_rows": len(events),
        "events_filtered": len(apply_state_filter(events)),
        "warehouse": WH,
    })
    if st.button("Refresh dashboard data"):
        st.cache_data.clear()
        st.rerun()
