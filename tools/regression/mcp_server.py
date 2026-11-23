#!/usr/bin/env python
"""WC3 regression MCP server (stdio, JSON-RPC 2.0, dependency-free).

Tools:
  - env_check       : verify paths / runtime prerequisites
  - build_test_map  : compile repo JASS + test harness, rebuild test map in workspace
  - run_regression  : launch WC3 (H drive) with a test map, wait for report, parse PASS/FAIL
  - last_report     : read/parse the latest Preload report without running the game

The server is intentionally dependency-free: it speaks the MCP stdio transport
(newline-delimited JSON-RPC) directly. It is started by DSH's MCP client and runs
as a normal user process, so it can launch WC3 / write the game directory
without the agent tool sandbox interfering.
"""
import json
import os
import re
import subprocess
import sys
import time

PROJ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KKWE = r"C:\Users\admin\Documents\WE\KKWE_nncouVer1.5.7.1"
W2L_PKG = os.path.join(KKWE, "plugin", "w3x2lni_zhCN_v2.7.3")
W2L_LUA = os.path.join(W2L_PKG, "bin", "w3x2lni-lua.exe")
BUILD_SCRIPT = os.path.join(PROJ, "tools", "regression", "build_test_harness.py")
BUILD_MAP_LUA = os.path.join(PROJ, "tools", "regression", "build_testmap.lua")
RUNNER_PS1 = os.path.join(PROJ, "tools", "regression", "run_regression.ps1")
PYTHON = sys.executable
POWERSHELL = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
DEFAULT_SRC_MAP = r"C:\Users\admin\Documents\WE\幻想之战-全模型\new0.1 26.11.15.w3x"
DEFAULT_GAME_DIR = r"H:\Game\Warcraft3"
REPORT_NAME = "war3regression.txt"
TMP_DIR = os.path.join(PROJ, ".team", "tmp")


def _child_env():
    """Env for child processes: pin TMP/TEMP into the workspace.

    The MCP server may be launched by DSH with an environment whose temp
    directory is not writable by JassHelper (GetTempFileName fails). Pointing
    TMP/TEMP at a workspace directory makes toolchain temp files reliable.
    """
    env = dict(os.environ)
    try:
        os.makedirs(TMP_DIR, exist_ok=True)
        env["TMP"] = TMP_DIR
        env["TEMP"] = TMP_DIR
    except Exception:
        pass
    return env


def _writable(path):
    try:
        if not path:
            return False
        os.makedirs(path, exist_ok=True)
        probe = os.path.join(path, ".mcp_write_probe")
        with open(probe, "w") as f:
            f.write("ok")
        os.remove(probe)
        return True
    except Exception:
        return False

TOOLS = [
    {
        "name": "env_check",
        "description": "Check WC3 regression environment: project paths, KKWE, H drive game dir, test maps, report path.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "build_test_map",
        "description": "Compile current repo JASS + test harness and rebuild a test-only map (source map is untouched).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "testId": {"type": "string", "description": "test map name, e.g. 11-08_test02 (default: auto)"},
                "srcMap": {"type": "string", "description": "source map template (default: production map path)"},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "run_regression",
        "description": "Launch WC3 with a test map on H drive, wait for the in-game regression report, return PASS/FAIL + checks.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "map": {"type": "string", "description": "test map path (default: newest testmaps/*.w3x)"},
                "gameDir": {"type": "string", "description": "WC3 install dir (default: H:\\Game\\Warcraft3)"},
                "timeoutSec": {"type": "integer", "description": "report wait timeout (default 180)"},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "last_report",
        "description": "Read and parse the most recent in-game regression report without launching the game.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "gameDir": {"type": "string", "description": "WC3 install dir (default: H:\\Game\\Warcraft3)"},
            },
            "additionalProperties": False,
        },
    },
]


def _run(cmd, cwd=None, timeout=600, env=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env or _child_env())
    return p.returncode, (p.stdout or ""), (p.stderr or "")


def _latest_test_map():
    d = os.path.join(PROJ, "testmaps")
    if not os.path.isdir(d):
        return None
    maps = [os.path.join(d, n) for n in os.listdir(d) if n.lower().endswith(".w3x")]
    maps.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return maps[0] if maps else None


def _report_path(game_dir):
    return os.path.join(game_dir, "Save", REPORT_NAME)


def _parse_report(path):
    raw = open(path, "rb").read()
    text = raw.decode("utf-8", "replace")
    if "\ufffd" in text:
        try:
            text = raw.decode("gbk", "replace")
        except Exception:
            pass
    lines = []
    for m in re.finditer(r'call\s+Preload\(\s*"((?:[^"\\]|\\.)*)"\s*\)', text):
        lines.append(m.group(1).replace('\\"', '"'))
    checks = [ln for ln in lines if ln.startswith("CHECK|")]
    fails = [ln for ln in checks if ln.split("|")[2:3] == ["FAIL"]]
    summary = next((ln for ln in reversed(lines) if ln.startswith("SUMMARY|")), "")
    return {
        "ok": True,
        "path": path,
        "lines": lines,
        "checks": checks,
        "fails": fails,
        "summary": summary,
        "result": "PASS" if "result=PASS" in summary else ("FAIL" if summary else "INCOMPLETE"),
    }


def tool_env_check():
    out = {"project": PROJ}
    out["kkwe"] = os.path.isdir(KKWE)
    out["w2lLua"] = os.path.isfile(W2L_LUA)
    out["runner"] = os.path.isfile(RUNNER_PS1)
    out["buildScript"] = os.path.isfile(BUILD_SCRIPT)
    out["python"] = PYTHON
    out["powershell"] = os.path.isfile(POWERSHELL)
    out["srcMapExists"] = os.path.isfile(DEFAULT_SRC_MAP)
    out["gameDirH"] = os.path.isdir(DEFAULT_GAME_DIR)
    out["gameDirD"] = os.path.isdir(r"D:\Game\Warcraft3\Warcraft3")
    latest = _latest_test_map()
    out["latestTestMap"] = latest
    out["latestTestMapMtime"] = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(os.path.getmtime(latest))) if latest else None
    out["reportPathH"] = _report_path(DEFAULT_GAME_DIR)
    out["reportExists"] = os.path.isfile(_report_path(DEFAULT_GAME_DIR))
    # 诊断：MCP 服务进程的 env/temp 是否可写（JassHelper GetTempFileName 依赖）
    out["cwd"] = os.getcwd()
    out["envTMP"] = os.environ.get("TMP")
    out["envTEMP"] = os.environ.get("TEMP")
    out["envTmpWritable"] = _writable(os.environ.get("TMP") or "")
    out["workspaceTmp"] = TMP_DIR
    out["workspaceTmpWritable"] = _writable(TMP_DIR)
    jh = os.path.join(PROJ, "tools", "precompile_check", "out", "jh")
    out["jhDir"] = jh
    out["jhWritable"] = _writable(jh)
    return out


def tool_build_test_map(test_id=None, src_map=None):
    src = src_map or DEFAULT_SRC_MAP
    if not os.path.isfile(src):
        return {"ok": False, "error": "source map not found: " + src}
    code, out, err = _run([PYTHON, BUILD_SCRIPT], cwd=PROJ, timeout=600)
    if code != 0:
        return {"ok": False, "error": "build_test_harness failed", "stdout": out[-4000:], "stderr": err[-2000:]}
    if not test_id:
        base = time.strftime("%m-%d")
        for i in range(1, 100):
            cand = "%s_test%02d" % (base, i)
            if not os.path.isfile(os.path.join(PROJ, "testmaps", cand + ".w3x")):
                test_id = cand
                break
        test_id = test_id or (base + "_test99")
    final = os.path.join(PROJ, "testmaps", test_id + ".w3x")
    compiled = os.path.join(PROJ, "tools", "precompile_check", "out", "harness_test_out.j")
    code, out2, err2 = _run(
        [W2L_LUA, BUILD_MAP_LUA, src, compiled, final],
        cwd=os.path.join(W2L_PKG, "bin"),
        timeout=900,
    )
    if code != 0 or not os.path.isfile(final):
        return {"ok": False, "error": "build_testmap failed", "stdout": out2[-4000:], "stderr": err2[-2000:]}
    return {
        "ok": True,
        "testMap": final,
        "size": os.path.getsize(final),
        "war3mapJBytes": os.path.getsize(compiled),
        "buildLogTail": out2[-1500:],
    }


def tool_run_regression(map_path=None, game_dir=None, timeout_sec=None):
    map_path = map_path or _latest_test_map()
    if not map_path or not os.path.isfile(map_path):
        return {"ok": False, "error": "no test map found; call build_test_map first"}
    game_dir = game_dir or DEFAULT_GAME_DIR
    timeout_sec = int(timeout_sec or 180)
    json_out = os.path.join(PROJ, ".team", "reports", "regression_last.json")
    os.makedirs(os.path.dirname(json_out), exist_ok=True)
    try:
        os.remove(json_out)
    except OSError:
        pass
    cmd = [
        POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", RUNNER_PS1,
        "-Map", map_path, "-GameDir", game_dir, "-TimeoutSec", str(timeout_sec),
        "-JsonOut", json_out,
    ]
    try:
        code, out, err = _run(cmd, cwd=PROJ, timeout=timeout_sec + 180)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "runner process timeout"}
    result = None
    if os.path.isfile(json_out):
        try:
            result = json.load(open(json_out, "r", encoding="utf-8-sig"))
        except Exception as e:
            result = {"jsonError": str(e)}
    return {
        "ok": bool(result and result.get("result") == "PASS"),
        "exitCode": code,
        "runnerResult": result,
        "stdoutTail": out[-5000:],
        "stderrTail": err[-2000:],
    }


def tool_last_report(game_dir=None):
    game_dir = game_dir or DEFAULT_GAME_DIR
    path = _report_path(game_dir)
    if not os.path.isfile(path):
        return {"ok": False, "error": "report not found: " + path}
    return _parse_report(path)


def dispatch(name, args):
    args = args or {}
    if name == "env_check":
        return tool_env_check()
    if name == "build_test_map":
        return tool_build_test_map(args.get("testId"), args.get("srcMap"))
    if name == "run_regression":
        return tool_run_regression(args.get("map"), args.get("gameDir"), args.get("timeoutSec"))
    if name == "last_report":
        return tool_last_report(args.get("gameDir"))
    raise KeyError("unknown tool: " + str(name))


def send(msg):
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def reply(req_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": req_id}
    if error is not None:
        msg["error"] = error
    else:
        msg["result"] = result
    send(msg)


def main():
    log = sys.stderr
    log.write("[wc3-regression-mcp] started, proj=%s\n" % PROJ)
    log.flush()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception as e:
            log.write("[wc3-regression-mcp] bad json: %s\n" % e)
            continue
        method = req.get("method")
        req_id = req.get("id")
        params = req.get("params") or {}
        try:
            if method == "initialize":
                reply(req_id, {
                    "protocolVersion": params.get("protocolVersion", "2025-06-18"),
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "wc3-regression", "version": "0.1.0"},
                })
            elif method in ("notifications/initialized", "initialized"):
                pass
            elif method == "ping":
                reply(req_id, {})
            elif method == "tools/list":
                reply(req_id, {"tools": TOOLS})
            elif method == "tools/call":
                name = params.get("name")
                args = params.get("arguments") or {}
                try:
                    result = dispatch(name, args)
                    reply(req_id, {"content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False)}], "isError": False})
                except Exception as e:
                    reply(req_id, {"content": [{"type": "text", "text": "tool error: %s" % e}], "isError": True})
            elif method == "resources/list":
                reply(req_id, {"resources": []})
            elif method == "prompts/list":
                reply(req_id, {"prompts": []})
            elif method in ("shutdown",):
                reply(req_id, {})
                break
            elif req_id is not None:
                reply(req_id, error={"code": -32601, "message": "method not found: " + str(method)})
        except Exception as e:
            log.write("[wc3-regression-mcp] handler error: %s\n" % e)
            log.flush()
            if req_id is not None:
                reply(req_id, error={"code": -32603, "message": str(e)})


if __name__ == "__main__":
    main()
