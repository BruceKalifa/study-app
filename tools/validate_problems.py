#!/usr/bin/env python3
"""Validate the problem bank in assets/problems/ (see docs/problem-schema.md).

Usage:
    python3 tools/validate_problems.py [--samples N] [--seed S] [--only ID_PREFIX] [-v]

* Implements the template expression grammar with its own tokenizer and
  recursive-descent parser (no Python eval):
      expr    := term (('+' | '-') term)*
      term    := unary (('*' | '/') unary)*
      unary   := '-' unary | power
      power   := primary ('^' unary)?        # right-assoc, tighter than unary '-'
      primary := number | name | name '(' args ')' | '(' expr ')'
  Functions: sqrt abs sin cos tan (degrees) log (base 10) ln exp min(a,b)
  max(a,b) round(x,n) floor ceil.  Constants: pi e.
* Checks schema + LaTeX rules of every file listed in assets/problems/_index.json.
* For every template, generates variants and checks answers / choiceExprs.

Exit status is non-zero when any error is found.  Standard library only.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PROB_DIR = os.path.join(ROOT, "assets", "problems")

VARIANTS_PER_TEMPLATE = 30
MAX_TRIES = 200
COLLISION_WARN_RATIO = 0.30


# ---------------------------------------------------------------------------
# Expression grammar


class ExprError(Exception):
    pass


FUNCS = {
    # name: arity
    "sqrt": 1, "abs": 1, "sin": 1, "cos": 1, "tan": 1, "log": 1, "ln": 1,
    "exp": 1, "min": 2, "max": 2, "round": 2, "floor": 1, "ceil": 1,
}
CONSTS = {"pi": math.pi, "e": math.e}
RESERVED = set(FUNCS) | set(CONSTS)


def tokenize(src: str):
    toks = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
            continue
        if c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
            start = i
            while i < n and src[i].isdigit():
                i += 1
            if i < n and src[i] == ".":
                i += 1
                while i < n and src[i].isdigit():
                    i += 1
            # optional exponent (1e3, 2.5E-4) — same as the Dart tokenizer
            if i < n and src[i] in "eE":
                j = i + 1
                if j < n and src[j] in "+-":
                    j += 1
                if j < n and src[j].isdigit():
                    i = j
                    while i < n and src[i].isdigit():
                        i += 1
            text = src[start:i]
            mant, expo = text, ""
            m = re.search(r"[eE]", text)
            if m:
                mant, expo = text[:m.start()], text[m.start():]
            if mant.startswith("."):
                mant = "0" + mant
            if mant.endswith("."):
                mant += "0"
            toks.append(("num", float(mant + expo), start))
            continue
        if c.isascii() and (c.isalpha() or c == "_"):
            start = i
            while i < n and src[i].isascii() and (src[i].isalnum() or src[i] == "_"):
                i += 1
            toks.append(("id", src[start:i], start))
            continue
        if c in "+-*/^(),":
            toks.append((c, c, i))
            i += 1
            continue
        raise ExprError(f"unexpected character {c!r} at {i}")
    toks.append(("end", "", n))
    return toks


class Parser:
    """Builds an AST of nested tuples:
    ('num', v) ('var', name) ('neg', x) ('bin', op, a, b) ('call', name, [args])"""

    def __init__(self, src: str):
        self.toks = tokenize(src)
        self.p = 0

    @property
    def cur(self):
        return self.toks[self.p]

    def eat(self, kind):
        if self.cur[0] != kind:
            raise ExprError(f"expected {kind!r} at {self.cur[2]}, got {self.cur[1]!r}")
        self.p += 1

    def parse(self):
        if self.cur[0] == "end":
            raise ExprError("empty expression")
        node = self.expr()
        if self.cur[0] != "end":
            raise ExprError(f"unexpected {self.cur[1]!r} at {self.cur[2]}")
        return node

    def expr(self):
        node = self.term()
        while self.cur[0] in ("+", "-"):
            op = self.cur[0]
            self.p += 1
            node = ("bin", op, node, self.term())
        return node

    def term(self):
        node = self.unary()
        while self.cur[0] in ("*", "/"):
            op = self.cur[0]
            self.p += 1
            node = ("bin", op, node, self.unary())
        return node

    def unary(self):
        if self.cur[0] == "-":
            self.p += 1
            return ("neg", self.unary())
        return self.power()

    def power(self):
        base = self.primary()
        if self.cur[0] == "^":
            self.p += 1
            return ("bin", "^", base, self.unary())  # right-assoc, allows 2^-1
        return base

    def primary(self):
        kind, val, pos = self.cur
        if kind == "num":
            self.p += 1
            return ("num", val)
        if kind == "(":
            self.p += 1
            node = self.expr()
            self.eat(")")
            return node
        if kind == "id":
            self.p += 1
            if self.cur[0] == "(":
                self.p += 1
                args = []
                if self.cur[0] != ")":
                    args.append(self.expr())
                    while self.cur[0] == ",":
                        self.p += 1
                        args.append(self.expr())
                self.eat(")")
                if val not in FUNCS:
                    raise ExprError(f"unknown function {val!r} at {pos}")
                if len(args) != FUNCS[val]:
                    raise ExprError(f"{val} takes {FUNCS[val]} argument(s), got {len(args)}")
                return ("call", val, args)
            if val in FUNCS:
                raise ExprError(f"function {val!r} used without arguments at {pos}")
            return ("var", val)
        if kind == "end":
            raise ExprError("unexpected end of expression")
        raise ExprError(f"unexpected {val!r} at {pos}")


_AST_CACHE: dict = {}


def parse_expr(src: str):
    if src not in _AST_CACHE:
        _AST_CACHE[src] = Parser(src).parse()
    return _AST_CACHE[src]


def expr_names(node, out=None):
    """Variable names referenced by an AST (constants excluded)."""
    if out is None:
        out = set()
    t = node[0]
    if t == "var":
        if node[1] not in CONSTS:
            out.add(node[1])
    elif t == "neg":
        expr_names(node[1], out)
    elif t == "bin":
        expr_names(node[2], out)
        expr_names(node[3], out)
    elif t == "call":
        for a in node[2]:
            expr_names(a, out)
    return out


def round_to(v: float, decimals: int) -> float:
    """Half away from zero, tolerant of binary noise (mirrors lib/core/format.dart)."""
    if not math.isfinite(v):
        return v
    f = 10.0 ** decimals
    scaled = abs(v) * f
    if not math.isfinite(scaled) or scaled >= 1e15:
        return v
    cleaned = float(f"{scaled:.15g}")
    r = math.floor(cleaned)
    if cleaned - r >= 0.5:
        r += 1
    r = r / f
    return -r if v < 0 else r


def _call(name, a):
    try:
        if name == "sqrt":
            return math.sqrt(a[0])
        if name == "abs":
            return abs(a[0])
        if name == "sin":
            return math.sin(math.radians(a[0]))
        if name == "cos":
            return math.cos(math.radians(a[0]))
        if name == "tan":
            return math.tan(math.radians(a[0]))
        if name == "log":
            return math.log10(a[0])
        if name == "ln":
            return math.log(a[0])
        if name == "exp":
            return math.exp(a[0])
        if name == "min":
            return min(a[0], a[1])
        if name == "max":
            return max(a[0], a[1])
        if name == "round":
            if not math.isfinite(a[1]):
                return math.nan
            return round_to(a[0], int(round_to(a[1], 0)))
        if name == "floor":
            return float(math.floor(a[0]))
        if name == "ceil":
            return float(math.ceil(a[0]))
    except (ValueError, OverflowError):
        return math.nan
    raise ExprError(f"unknown function {name}")


def eval_ast(node, env):
    t = node[0]
    if t == "num":
        return node[1]
    if t == "var":
        name = node[1]
        if name in env:
            return float(env[name])
        if name in CONSTS:
            return CONSTS[name]
        raise ExprError(f"unknown name {name!r}")
    if t == "neg":
        return -eval_ast(node[1], env)
    if t == "bin":
        a = eval_ast(node[2], env)
        b = eval_ast(node[3], env)
        op = node[1]
        if op == "+":
            return a + b
        if op == "-":
            return a - b
        if op == "*":
            return a * b
        if op == "/":
            if b == 0:
                return math.nan if a == 0 else math.copysign(math.inf, a)
            return a / b
        if op == "^":
            try:
                r = math.pow(a, b)
            except (ValueError, OverflowError):
                return math.nan
            return r
    if t == "call":
        return _call(node[1], [eval_ast(x, env) for x in node[2]])
    raise ExprError(f"bad node {node!r}")


def evaluate(src: str, env=None) -> float:
    return eval_ast(parse_expr(src), env or {})


def fmt_num(v: float, max_decimals: int = 3) -> str:
    """Mirrors fmtNum in lib/core/format.dart."""
    if math.isnan(v):
        return "NaN"
    if math.isinf(v):
        return "∞" if v > 0 else "-∞"
    d = max(0, max_decimals)
    r = round_to(v, d)
    if r == 0:
        return "0"
    if r == math.floor(r) and abs(r) < 1e15:
        return str(int(r))
    s = f"{r:.{min(d, 20)}f}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


TEST_VECTORS = [
    ("2+3*4", {}, 14), ("-2^2", {}, -4), ("2^3^2", {}, 512),
    ("sqrt(16)+abs(-3)", {}, 7), ("sin(30)", {}, 0.5), ("cos(60)*2", {}, 1),
    ("log(1000)", {}, 3), ("ln(e)", {}, 1), ("round(3.14159,2)", {}, 3.14),
    ("min(3,max(1,2))", {}, 2), ("(1+2)*(3-5)/4", {}, -1.5),
    ("0.5*a*t^2", {"a": 2, "t": 3}, 9), ("floor(2.7)+ceil(2.1)", {}, 5),
    ("2^-1", {}, 0.5), ("-(2)^2", {}, -4), ("(-2)^2", {}, 4), ("10/4*2", {}, 5),
    ("8-3-2", {}, 3), ("2*-3", {}, -6), (".5+1.", {}, 1.5),
]
BAD_EXPRS = ["2+", "(1+2", "sin", "foo(1)", "min(1)", "round(2)", "2 3", "a$b", "+2", ""]


def self_test():
    errs = []
    for src, env, want in TEST_VECTORS:
        try:
            got = evaluate(src, env)
        except ExprError as ex:
            errs.append(f"{src}: {ex}")
            continue
        if abs(got - want) > 1e-9:
            errs.append(f"{src} = {got}, expected {want}")
    for src in BAD_EXPRS:
        try:
            parse_expr(src)
            errs.append(f"{src!r} should not parse")
        except ExprError:
            pass
    return errs


# ---------------------------------------------------------------------------
# Text checks

HANGUL_RE = re.compile("[\u1100-\u11FF\u3130-\u318F\uAC00-\uD7A3]")
PLACEHOLDER_RE = re.compile(r"\[\[(.*?)\]\]")
NAME_RE = re.compile(r"^[a-z][a-z0-9]*$")
CMD_RE = re.compile(r"\\([A-Za-z]+|.)")
ALLOWED_CMDS = set(
    r"""frac sqrt times cdot div pm le ge ne approx theta alpha beta lambda omega
    Delta pi mu rho sigma circ vec overline text left right infty sum int lim log
    sin cos tan""".split()
) | {",", ";", "!", " ", "to", "ln", "cdots", "quad", "neq", "leq", "geq", "lt",
     "gt", "gamma", "phi", "varphi", "epsilon", "tau", "Omega", "rightarrow",
     "Rightarrow", "prime", "%", "{", "}", "|", "angle", "triangle", "perp",
     "parallel", "propto", "Phi"}


def math_segments(s: str):
    parts = s.split("$")
    return parts[1::2]


def check_text(s: str, where: str, errs: list, warns: list, allow_placeholders=False):
    if not isinstance(s, str):
        errs.append(f"{where}: not a string")
        return
    if s.count("$") % 2:
        errs.append(f"{where}: unbalanced $ ({s.count('$')} signs)")
    if "\\begin" in s:
        errs.append(f"{where}: \\begin is not allowed")
    if "\\\\" in s:
        errs.append(f"{where}: '\\\\' (LaTeX line break) is not allowed")
    for seg in math_segments(s):
        if HANGUL_RE.search(seg):
            errs.append(f"{where}: Korean text inside $...$: ${seg}$")
        for m in re.finditer(r"\\text\{([^}]*)\}", seg):
            if not m.group(1).isascii():
                errs.append(f"{where}: non-ASCII inside \\text{{}}: {m.group(1)!r}")
        for m in CMD_RE.finditer(seg):
            if m.group(1) not in ALLOWED_CMDS:
                warns.append(f"{where}: LaTeX command \\{m.group(1)} is not in the allowed list")
        if seg.count("{") != seg.count("}"):
            errs.append(f"{where}: unbalanced braces in ${seg}$")
    if not allow_placeholders and "[[" in s:
        errs.append(f"{where}: [[...]] placeholder outside a template")


def check_placeholders(s: str, where: str, names: set, errs: list, allow_v=False):
    for m in PLACEHOLDER_RE.finditer(s or ""):
        body = m.group(1)
        if body.startswith("="):
            try:
                used = expr_names(parse_expr(body[1:]))
            except ExprError as ex:
                errs.append(f"{where}: [[{body}]] does not parse: {ex}")
                continue
            bad = used - names
            if bad:
                errs.append(f"{where}: [[{body}]] uses undefined name(s) {sorted(bad)}")
        else:
            if body == "v" and allow_v:
                continue
            if body not in names:
                errs.append(f"{where}: placeholder [[{body}]] is not a defined param")
    if "[[" in PLACEHOLDER_RE.sub("", s or ""):
        errs.append(f"{where}: unterminated [[ placeholder")


def render(s: str, env: dict) -> str:
    def rep(m):
        body = m.group(1)
        if body.startswith("="):
            return fmt_num(evaluate(body[1:], env), 3)
        return fmt_num(float(env[body]), 3)
    return PLACEHOLDER_RE.sub(rep, s)


NUM_RE = re.compile(r"^-?(\d+(\.\d+)?|\.\d+)$")
FRAC_RE = re.compile(r"^-?\d+/\d+$")


def parse_answer_number(s: str):
    s = s.strip()
    if NUM_RE.match(s):
        return float(s)
    if FRAC_RE.match(s):
        a, b = s.lstrip("-").split("/")
        if int(b) == 0:
            return None
        v = int(a) / int(b)
        return -v if s.startswith("-") else v
    return None


# ---------------------------------------------------------------------------
# Template variants


def param_choices(spec: dict):
    if "values" in spec:
        return [float(v) for v in spec["values"]]
    lo, hi = float(spec["min"]), float(spec["max"])
    step = float(spec.get("step", 1))
    n = int(math.floor((hi - lo) / step + 1e-9))
    return [round(lo + k * step, 10) for k in range(n + 1)]


def same(a, b, tol=1e-9):
    return abs(a - b) <= tol * max(1.0, abs(a), abs(b))


def make_variant(tpl: dict, rng: random.Random):
    """Returns (env, tries) or (None, tries) if no params satisfy `require`."""
    pools = {k: param_choices(v) for k, v in tpl["params"].items()}
    reqs = tpl.get("require", [])
    for tries in range(1, MAX_TRIES + 1):
        env = {k: rng.choice(v) for k, v in pools.items()}
        ok = True
        for r in reqs:
            val = evaluate(r, env)
            if not (math.isfinite(val) and val > 0):
                ok = False
                break
        if ok:
            return env, tries
    return None, MAX_TRIES


def choice_labels(tpl: dict, env: dict):
    nd = tpl.get("round", 3)
    fmt = tpl.get("choiceFormat", "[[v]]") or "[[v]]"
    vals = [evaluate(c, env) for c in tpl["choiceExprs"]]
    return vals, [fmt.replace("[[v]]", fmt_num(v, nd)) for v in vals]


def validate_template(p: dict, where: str, errs: list, warns: list, stats: dict, rng):
    tpl = p["template"]
    if not isinstance(tpl, dict):
        errs.append(f"{where}: template must be an object")
        return
    e0 = len(errs)
    for k in ("params", "stem", "answer"):
        if k not in tpl:
            errs.append(f"{where}: template missing '{k}'")
    if not isinstance(tpl.get("params", {}), dict):
        errs.append(f"{where}: template params must be an object")
    if len(errs) > e0:
        return
    params = tpl["params"]
    names = set(params)
    for name, spec in params.items():
        w = f"{where}.params.{name}"
        if not NAME_RE.match(name):
            errs.append(f"{w}: param names must be lowercase letters/digits")
        if name in RESERVED or name == "v":
            errs.append(f"{w}: '{name}' is reserved")
        if "values" in spec:
            if not spec["values"] or not all(isinstance(x, (int, float)) for x in spec["values"]):
                errs.append(f"{w}: 'values' must be a non-empty number list")
                continue
        elif "min" in spec and "max" in spec:
            st = spec.get("step", 1)
            if st <= 0 or spec["max"] < spec["min"]:
                errs.append(f"{w}: bad min/max/step")
                continue
        else:
            errs.append(f"{w}: needs either values or min/max")
            continue
        for v in param_choices(spec):
            if abs(round_to(v, 3) - v) > 1e-9:
                warns.append(f"{w}: value {v} has more than 3 decimals (display rounds it)")
                break
    # expressions parse + refer to defined names
    exprs = [("answer", tpl["answer"])]
    exprs += [(f"require[{i}]", r) for i, r in enumerate(tpl.get("require", []))]
    exprs += [(f"choiceExprs[{i}]", c) for i, c in enumerate(tpl.get("choiceExprs") or [])]
    for label, src in exprs:
        try:
            bad = expr_names(parse_expr(src)) - names
            if bad:
                errs.append(f"{where}.template.{label}: undefined name(s) {sorted(bad)} in {src!r}")
        except ExprError as ex:
            errs.append(f"{where}.template.{label}: {src!r} does not parse: {ex}")
    for key in ("stem", "solution", "hint"):
        if key in tpl:
            check_text(tpl[key], f"{where}.template.{key}", errs, warns, allow_placeholders=True)
            check_placeholders(tpl[key], f"{where}.template.{key}", names, errs)
    if "choiceFormat" in tpl:
        cf = tpl["choiceFormat"]
        check_placeholders(cf, f"{where}.template.choiceFormat", names, errs, allow_v=True)
        if "[[v]]" not in cf:
            errs.append(f"{where}.template.choiceFormat: must contain [[v]]")
    if "round" in tpl and not (isinstance(tpl["round"], int) and 0 <= tpl["round"] <= 6):
        errs.append(f"{where}.template.round: must be an integer 0..6")
    is_choice = p.get("type") == "choice"
    ce = tpl.get("choiceExprs")
    if is_choice:
        if not isinstance(ce, list) or len(ce) != 5:
            errs.append(f"{where}: choice template needs exactly 5 choiceExprs")
            return
    elif ce is not None:
        errs.append(f"{where}: short template must not have choiceExprs")
    if len(errs) > e0:
        return

    nd = tpl.get("round", 3)
    collisions = dup_distractors = 0
    non_integer = 0
    samples = []
    for i in range(VARIANTS_PER_TEMPLATE):
        env, tries = make_variant(tpl, rng)
        if env is None:
            errs.append(f"{where}: no parameter set satisfies `require` in {MAX_TRIES} tries")
            return
        try:
            ans = evaluate(tpl["answer"], env)
        except ExprError as ex:
            errs.append(f"{where}: answer evaluation failed: {ex}")
            return
        if not math.isfinite(ans):
            errs.append(f"{where}: answer not finite for {env}")
            return
        if "round" not in tpl and abs(ans - round(ans)) > 1e-9:
            non_integer += 1
        try:
            for key in ("stem", "solution", "hint"):
                if key in tpl:
                    txt = render(tpl[key], env)
                    if "NaN" in txt or "∞" in txt:
                        errs.append(f"{where}.template.{key}: non-finite value for {env}")
                        return
                    if re.search(r"[+\-]\s*-\d", "".join(math_segments(txt))):
                        warns.append(f"{where}.template.{key}: rendered sign clash ('+ -n') for {env}")
            sample = {"env": env, "stem": render(tpl["stem"], env), "answer": fmt_num(ans, nd)}
        except ExprError as ex:
            errs.append(f"{where}: placeholder evaluation failed: {ex}")
            return
        if is_choice:
            vals, labels = choice_labels(tpl, env)
            if not all(math.isfinite(v) for v in vals):
                errs.append(f"{where}: non-finite choice value for {env}")
                return
            if not same(vals[0], ans):
                errs.append(f"{where}: choiceExprs[0]={vals[0]} != answer={ans} for {env}")
                return
            if any(lbl == labels[0] for lbl in labels[1:]):
                collisions += 1
            if len(set(labels[1:])) < 4:
                dup_distractors += 1
            sample["choices"] = labels
        samples.append(sample)
    stats["variants"] += VARIANTS_PER_TEMPLATE
    if is_choice:
        ratio = collisions / VARIANTS_PER_TEMPLATE
        stats["collision_rates"].append(ratio)
        if ratio > COLLISION_WARN_RATIO:
            warns.append(f"{where}: a distractor equals the answer in {ratio:.0%} of variants")
        if dup_distractors / VARIANTS_PER_TEMPLATE > 0.5:
            warns.append(f"{where}: distractors duplicate each other in "
                         f"{dup_distractors / VARIANTS_PER_TEMPLATE:.0%} of variants")
    if non_integer:
        warns.append(f"{where}: answer is non-integer in {non_integer}/{VARIANTS_PER_TEMPLATE} "
                     f"variants but template has no 'round'")
    stats["samples"][p["id"]] = samples


# ---------------------------------------------------------------------------
# Problem / file checks

REQUIRED = ("id", "unit", "topic", "difficulty", "type", "stem", "answer", "solution")


def validate_problem(p: dict, where: str, errs, warns, stats, rng):
    e0 = len(errs)
    for k in REQUIRED:
        if k not in p:
            errs.append(f"{where}: missing '{k}'")
    if len(errs) > e0:
        return
    for k in ("id", "unit", "topic", "type", "stem", "answer", "solution"):
        if not isinstance(p[k], str) or not p[k].strip():
            errs.append(f"{where}: '{k}' must be a non-empty string")
    d = p["difficulty"]
    if not (isinstance(d, int) and not isinstance(d, bool) and 1 <= d <= 5):
        errs.append(f"{where}: difficulty must be an integer 1..5")
    t = p["type"]
    if t == "choice":
        ch = p.get("choices")
        if not isinstance(ch, list) or len(ch) != 5:
            errs.append(f"{where}: choice problem needs exactly 5 choices")
        else:
            for i, c in enumerate(ch):
                if not isinstance(c, str) or not c.strip():
                    errs.append(f"{where}.choices[{i}]: empty")
                else:
                    check_text(c, f"{where}.choices[{i}]", errs, warns)
            if len(set(ch)) != 5:
                errs.append(f"{where}: duplicate choices {ch}")
        if p["answer"] not in ("1", "2", "3", "4", "5"):
            errs.append(f"{where}: choice answer must be '1'..'5', got {p['answer']!r}")
    elif t == "short":
        if "choices" in p:
            errs.append(f"{where}: short problem must not have choices")
        if parse_answer_number(p["answer"]) is None:
            errs.append(f"{where}: short answer {p['answer']!r} is not a number/fraction")
        tol = p.get("tolerance", 0)
        if not isinstance(tol, (int, float)) or tol < 0:
            errs.append(f"{where}: tolerance must be a non-negative number")
    else:
        errs.append(f"{where}: type must be 'choice' or 'short'")
    for k in ("stem", "solution", "hint"):
        if k in p:
            check_text(p[k], f"{where}.{k}", errs, warns)
    if "boxItems" in p:
        bi = p["boxItems"]
        if not isinstance(bi, list) or not bi:
            errs.append(f"{where}: boxItems must be a non-empty list")
        else:
            for i, b in enumerate(bi):
                check_text(b, f"{where}.boxItems[{i}]", errs, warns)
                if not re.match(r"^[ㄱ-ㅎ]\. ", b):
                    warns.append(f"{where}.boxItems[{i}]: expected to start with 'ㄱ. ' style label")
    if "tags" in p and not (isinstance(p["tags"], list) and all(isinstance(x, str) for x in p["tags"])):
        errs.append(f"{where}: tags must be a string list")
    if "hint" not in p:
        stats["no_hint"] += 1
    if "template" in p:
        validate_template(p, where, errs, warns, stats, rng)


def validate_file(fname: str, seen_ids: dict, errs, warns, rng):
    path = os.path.join(PROB_DIR, fname)
    stats = {"variants": 0, "collision_rates": [], "samples": {}, "no_hint": 0}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as ex:
        errs.append(f"{fname}: cannot load: {ex}")
        return None, stats
    for k in ("subject", "subjectId", "color", "problems"):
        if k not in data:
            errs.append(f"{fname}: missing top-level '{k}'")
    if not re.match(r"^#[0-9A-Fa-f]{6}$", str(data.get("color", ""))):
        errs.append(f"{fname}: color must be #RRGGBB")
    probs = data.get("problems") or []
    for i, p in enumerate(probs):
        pid = p.get("id", f"#{i}")
        where = f"{fname}:{pid}"
        if pid in seen_ids:
            errs.append(f"{where}: duplicate id (also in {seen_ids[pid]})")
        seen_ids[pid] = fname
        validate_problem(p, where, errs, warns, stats, rng)
    return data, stats


def summarize(fname, data, stats, n_err, n_warn):
    probs = data.get("problems", [])
    n = len(probs)
    n_tpl = sum(1 for p in probs if "template" in p)
    n_choice = sum(1 for p in probs if p.get("type") == "choice")
    n_box = sum(1 for p in probs if p.get("boxItems"))
    diff = {d: 0 for d in range(1, 6)}
    for p in probs:
        if p.get("difficulty") in diff:
            diff[p["difficulty"]] += 1
    units = {}
    for p in probs:
        units[p.get("unit", "?")] = units.get(p.get("unit", "?"), 0) + 1
    rates = stats["collision_rates"]
    coll = f"{max(rates):.0%} max / {sum(rates) / len(rates):.0%} avg" if rates else "-"
    print(f"== {fname}  [{data.get('subject')} / {data.get('subjectId')}]")
    print(f"   problems {n}: choice {n_choice} (보기형 {n_box}), short {n - n_choice}; "
          f"templates {n_tpl} ({(n_tpl / n if n else 0):.0%}), variants checked {stats['variants']}")
    print("   difficulty " + "  ".join(f"{d}:{c}" for d, c in diff.items())
          + f"   no-hint {stats['no_hint']}")
    print("   units " + ", ".join(f"{u} {c}" for u, c in units.items()))
    print(f"   distractor=answer collisions: {coll}")
    print(f"   errors {n_err}, warnings {n_warn}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--samples", type=int, default=0, help="print N sample variants per template")
    ap.add_argument("--only", default="", help="limit --samples output to ids with this prefix")
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("-v", "--verbose", action="store_true", help="print every warning")
    args = ap.parse_args()

    errs, warns = [], []
    st = self_test()
    if st:
        for e in st:
            print("SELF-TEST FAIL:", e)
        sys.exit(2)
    print(f"expression self-test: {len(TEST_VECTORS)} vectors + {len(BAD_EXPRS)} bad inputs OK")

    idx_path = os.path.join(PROB_DIR, "_index.json")
    try:
        with open(idx_path, encoding="utf-8") as f:
            files = json.load(f)["files"]
    except (OSError, ValueError, KeyError) as ex:
        print(f"ERROR: cannot read {idx_path}: {ex}")
        sys.exit(1)
    if not files:
        print("ERROR: _index.json lists no files")
        sys.exit(1)

    rng = random.Random(args.seed)
    seen = {}
    total = {"problems": 0, "templates": 0}
    for fname in files:
        e0, w0 = len(errs), len(warns)
        data, stats = validate_file(fname, seen, errs, warns, rng)
        if data is None:
            continue
        summarize(fname, data, stats, len(errs) - e0, len(warns) - w0)
        total["problems"] += len(data.get("problems", []))
        total["templates"] += sum(1 for p in data.get("problems", []) if "template" in p)
        if args.samples:
            for pid, samples in stats["samples"].items():
                if args.only and not pid.startswith(args.only):
                    continue
                print(f"   -- samples for {pid}")
                for s in samples[: args.samples]:
                    env = ", ".join(f"{k}={fmt_num(v, 4)}" for k, v in s["env"].items())
                    print(f"      [{env}]")
                    print("      " + s["stem"].replace("\n", "\n      "))
                    if "choices" in s:
                        print(f"      choices (first = correct): {s['choices']}")
                    print(f"      answer: {s['answer']}")
    print()
    if warns:
        print(f"WARNINGS ({len(warns)}):")
        for w in warns if args.verbose else warns[:40]:
            print("  -", w)
        if len(warns) > 40 and not args.verbose:
            print(f"  ... {len(warns) - 40} more (use -v)")
    if errs:
        print(f"ERRORS ({len(errs)}):")
        for e in errs:
            print("  -", e)
    print(f"TOTAL: {len(files)} files, {total['problems']} problems, {total['templates']} templates, "
          f"{len(errs)} errors, {len(warns)} warnings")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
