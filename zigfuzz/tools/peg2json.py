#!/usr/bin/env python3
"""Convert Zig's official PEG grammar into a Grammar-Mutator JSON grammar.

The PEG is a recogniser; we need a generator, so the translation is deliberately
lossy in three ways:

  * ordered choice `/` becomes unordered choice -- the generator picks uniformly,
    which is what gives us variety
  * syntactic predicates `!x` / `&x` are dropped; they constrain parsing, and a
    generator that honoured them would need backtracking it cannot do
  * `?` `*` `+` are expanded into helper rules, because the JSON format is a plain
    CFG: a rule is a list of alternatives, each a flat list of tokens

Output shape matches the daScript grammar: {"<Rule>": [[token, ...], ...]} where a
token is "<Rule>" for a nonterminal and a bare string for a literal.
"""
import json
import re
import sys

# ---------------------------------------------------------------- tokenising ---

class Src:
    def __init__(self, text):
        self.s = text
        self.i = 0

    def ws(self, newlines=True):
        while self.i < len(self.s):
            c = self.s[self.i]
            if c == '#':
                while self.i < len(self.s) and self.s[self.i] != '\n':
                    self.i += 1
            elif c in ' \t' or (newlines and c in '\r\n'):
                self.i += 1
            else:
                break

    def eof(self):
        self.ws()
        return self.i >= len(self.s)

    def peek(self, n=1):
        return self.s[self.i:self.i + n]

    def take(self, lit):
        self.ws()
        if self.s.startswith(lit, self.i):
            self.i += len(lit)
            return True
        return False


# ------------------------------------------------------------------ PEG AST ---
# ('seq', [items]) ('alt', [items]) ('ref', name) ('lit', text)
# ('cls', [chars]) ('any',) ('opt', item) ('star', item) ('plus', item)

RULE_HEAD = re.compile(r'[A-Za-z_][A-Za-z0-9_]*\s*<-')


def parse_grammar(text):
    src = Src(text)
    rules = {}
    order = []
    while not src.eof():
        src.ws()
        m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)\s*<-', src.s[src.i:])
        if not m:
            raise SystemExit('expected a rule head at offset %d: %r'
                             % (src.i, src.s[src.i:src.i + 60]))
        name = m.group(1)
        src.i += m.end()
        rules[name] = parse_alt(src)
        order.append(name)
    return rules, order


def parse_alt(src):
    items = [parse_seq(src)]
    while True:
        save = src.i
        src.ws()
        if src.peek() == '/' and src.peek(2) != '//':
            src.i += 1
            items.append(parse_seq(src))
        else:
            src.i = save
            break
    return ('alt', items) if len(items) > 1 else items[0]


def parse_seq(src):
    items = []
    while True:
        save = src.i
        src.ws()
        if src.i >= len(src.s):
            break
        # a new rule head ends the current rule
        if RULE_HEAD.match(src.s[src.i:]):
            src.i = save
            break
        if src.peek() in (')', '/', '') :
            src.i = save
            break
        it = parse_prefixed(src)
        if it is None:
            src.i = save
            break
        items.append(it)
    if not items:
        return ('seq', [])
    return ('seq', items) if len(items) > 1 else items[0]


def parse_prefixed(src):
    src.ws()
    neg = False
    if src.peek() in '!&':
        src.i += 1
        neg = True
    prim = parse_primary(src)
    if prim is None:
        return None
    # suffix
    while src.i < len(src.s) and src.peek() in '?*+':
        c = src.peek()
        src.i += 1
        prim = {'?': 'opt', '*': 'star', '+': 'plus'}[c], prim
    if neg:
        return ('seq', [])      # predicates generate nothing
    return prim


def parse_primary(src):
    src.ws()
    if src.i >= len(src.s):
        return None
    c = src.peek()
    if c == '(':
        src.i += 1
        inner = parse_alt(src)
        src.ws()
        if not src.take(')'):
            raise SystemExit('unclosed group near %r' % src.s[src.i:src.i + 40])
        return inner
    if c in ("'", '"'):
        return ('lit', parse_literal(src))
    if c == '[':
        return ('cls', parse_class(src))
    if c == '.':
        src.i += 1
        return ('any',)
    m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', src.s[src.i:])
    if m:
        src.i += m.end()
        return ('ref', m.group(0))
    return None


ESCAPES = {'n': '\n', 'r': '\r', 't': '\t', '\\': '\\', "'": "'",
           '"': '"', ']': ']', '-': '-', '0': '\0'}


def read_escape(s, i):
    """s[i] is the char after a backslash. Returns (char, next_index)."""
    c = s[i]
    if c in ESCAPES:
        return ESCAPES[c], i + 1
    if c.isdigit():                      # octal, e.g. \364
        j = i
        while j < len(s) and j < i + 3 and s[j].isdigit():
            j += 1
        return chr(int(s[i:j], 8) & 0xFF), j
    if c == 'x':
        return chr(int(s[i + 1:i + 3], 16)), i + 3
    return c, i + 1


def parse_literal(src):
    quote = src.peek()
    assert quote in ("'", '"')
    src.i += 1
    out = []
    while src.i < len(src.s) and src.peek() != quote:
        if src.peek() == '\\':
            src.i += 1
            ch, src.i = read_escape(src.s, src.i)
            out.append(ch)
        else:
            out.append(src.s[src.i])
            src.i += 1
    src.i += 1
    return ''.join(out)


def parse_class(src):
    assert src.peek() == '['
    src.i += 1
    neg = False
    if src.peek() == '^':
        neg = True
        src.i += 1
    chars = []
    while src.i < len(src.s) and src.peek() != ']':
        if src.peek() == '\\':
            src.i += 1
            ch, src.i = read_escape(src.s, src.i)
        else:
            ch = src.s[src.i]
            src.i += 1
        if src.peek() == '-' and src.i + 1 < len(src.s) and src.s[src.i + 1] != ']':
            src.i += 1
            if src.peek() == '\\':
                src.i += 1
                hi, src.i = read_escape(src.s, src.i)
            else:
                hi = src.s[src.i]
                src.i += 1
            chars.extend(chr(x) for x in range(ord(ch), ord(hi) + 1))
        else:
            chars.append(ch)
    src.i += 1
    if neg:
        # A negated class is only ever used for "any char but these"; a few safe
        # printable characters are enough for a generator and keep output sane.
        pool = [c for c in 'abcXYZ019 _.' if c not in chars]
        chars = pool or ['a']
    return chars


# ------------------------------------------------------------------ lowering ---
# PEG AST -> {"<Rule>": [[token, ...], ...]}. Groups and quantifiers become
# helper rules because the target format has no nesting: `x*` turns into a
# right-recursive helper, `x?` into a helper with an empty alternative.

class Lowerer:
    def __init__(self, rules):
        self.rules = rules
        self.out = {}
        self.helpers = 0
        self.owner = 'x'

    def new_helper(self, hint):
        # Helpers are named after the rule that owns them so the tuning layer can
        # address them; auto-numbered names alone would not be stable targets.
        self.helpers += 1
        return '%s_%s%d' % (self.owner, hint, self.helpers)

    def tokens(self, node):
        """Flatten a node into a token list, creating helpers as needed."""
        if node[0] == 'seq':
            toks = []
            for it in node[1]:
                toks.extend(self.tokens(it))
            return toks
        t = self.emit(node)
        return [] if t is None else [t]

    def emit(self, node):
        kind = node[0]
        if kind == 'ref':
            return '<%s>' % node[1]
        if kind == 'lit':
            return node[1] if node[1] else None
        if kind == 'cls':
            name = self.new_helper('cls')
            self.out['<%s>' % name] = [[c] for c in node[1]] or [[]]
            return '<%s>' % name
        if kind == 'any':
            name = self.new_helper('any')
            self.out['<%s>' % name] = [[c] for c in 'abcXYZ019 _']
            return '<%s>' % name
        if kind == 'alt':
            name = self.new_helper('alt')
            self.out['<%s>' % name] = [self.tokens(b) for b in node[1]]
            return '<%s>' % name
        if kind == 'opt':
            name = self.new_helper('opt')
            self.out['<%s>' % name] = [[], self.tokens(node[1])]
            return '<%s>' % name
        if kind == 'star':
            name = self.new_helper('star')
            inner = self.tokens(node[1])
            self.out['<%s>' % name] = [[], inner + ['<%s>' % name]]
            return '<%s>' % name
        if kind == 'plus':
            name = self.new_helper('plus')
            inner = self.tokens(node[1])
            self.out['<%s>' % name] = [inner, inner + ['<%s>' % name]]
            return '<%s>' % name
        raise SystemExit('cannot lower node kind %r' % kind)

    def run(self):
        for name, body in self.rules.items():
            self.owner = name
            alts = body[1] if body[0] == 'alt' else [body]
            self.out['<%s>' % name] = [self.tokens(a) for a in alts]
        return self.out


# Rules replaced wholesale. The PEG defines these down to the byte, which a
# generator would turn into unreadable noise with a near-zero chance of naming
# something that exists. A small curated set is what makes the output compile
# often enough to reach past the parser -- the same reason daScript's grammar
# pins <name> to a fixed list.
def _tok(words):
    """Token replacements must carry the trailing `skip` the PEG gives them;
    without it the generator emits `i||` or `c{` and Zig rejects the spacing."""
    return [[w + ' '] for w in words]


REPLACE = {
    'skip': [[' ']],
    'eof': [[]],
    'IDENTIFIER': _tok(('a', 'b', 'c', 'd', 'x', 'y', 'z', 'i', 'n', 'v',
                        'foo', 'bar', 'baz', 'T', 'U', 'S', 'E', 'f0', 'f1', 'v0', 'v1')),
    'BUILTINIDENTIFIER': _tok(('@as', '@sizeOf', '@TypeOf', '@intCast',
                               '@truncate', '@bitCast', '@min', '@max')),
    'INTEGER': _tok(('0', '1', '2', '7', '42', '255', '0x1f')),
    'FLOAT': _tok(('0.0', '1.5', '2.5e3')),
    'STRINGLITERALSINGLE': _tok(('"s"', '""', '"abc"')),
    'STRINGLITERAL': _tok(('"s"', '""', '"abc"')),
    'CHAR_LITERAL': _tok(("'a'", "'0'")),
    # Comments carry no syntax we want to explore and wreck the output layout.
    'doc_comment': [[]],
    'container_doc_comment': [[]],
    'line_comment': [[]],
    'line_string': [['"s"']],
}


# --------------------------------------------------------------- tuning ---
# Applied to the lowered JSON. Each entry exists because it was the top line of
# an `zig ast-check` error histogram over 200 generated programs, in that order.

# `TypeExpr` bottoms out at IDENTIFIER, and a fixed identifier set never names a
# real type -- "expected type expression" was 51 of 179 failures on its own.
PRIM_TYPES = ('u8', 'u16', 'u32', 'u64', 'i8', 'i32', 'i64', 'usize', 'isize',
              'bool', 'void', 'f32', 'f64', 'type', 'anyerror', 'comptime_int')

POST_REPLACE = {
    # A field with no name is a tuple field, and a file cannot be a tuple (22).
    '<ContainerField>': [
        ['<IDENTIFIER>', '<COLON>', '<TypeExpr>'],
        ['<IDENTIFIER>', '<COLON>', '<TypeExpr>', '<EQUAL>', '<Expr>'],
    ],
    # "variables must be initialized" (9): the PEG makes the initialiser optional,
    # which is only legal for extern/threadlocal declarations.
    '<GlobalVarDecl>': [['<VarDeclProto>', '<EQUAL>', '<Expr>', '<SEMICOLON>']],
    # "function prototype has parameter after varargs" (11): the bare DOT3
    # alternative can land anywhere in the list, and varargs must come last.
    '<ParamDecl>': [
        ['<IDENTIFIER>', '<COLON>', '<ParamType>'],
        ['<KEYWORD_comptime>', '<IDENTIFIER>', '<COLON>', '<ParamType>'],
        ['<KEYWORD_noalias>', '<IDENTIFIER>', '<COLON>', '<ParamType>'],
    ],
    # "non-extern function has no body" (9): keep the modifiers, but only extern
    # may end a prototype with a semicolon.
    '<Decl>': [
        ['<FnProto>', '<Block>'],
        ['<KEYWORD_export>', '<FnProto>', '<Block>'],
        ['<KEYWORD_inline>', '<FnProto>', '<Block>'],
        ['<KEYWORD_extern>', '<FnProto>', '<SEMICOLON>'],
        ['<GlobalVarDecl>'],
        ['<KEYWORD_threadlocal>', '<GlobalVarDecl>'],
    ],
}

# Alternatives added to a rule, repeated to weight them.
POST_BIAS = {
    '<PrimaryTypeExpr>': [([p + ' '], 2) for p in PRIM_TYPES],
}


# Right-recursive star helpers the generator will happily ride forever. The
# operator stars are the worst: their alternatives are one or two characters, so
# a size budget buys hundreds of them and the program is operator soup with no
# payload -- `d : [ : asm ( return * try & continue [ if ( -% resume & ~ -% ...`.
# Bounding them to a couple of repetitions is what lets a real program appear.
POST_BOUND = {
    '<PrefixExpr_star68>': 2,     # PrefixOp*      ! ~ - -% & try await
    '<TypeExpr_star88>': 2,       # PrefixTypeOp*  ? [] * const volatile
    '<SuffixExpr_star90>': 2,     # SuffixOp*      .x .* [i] ()
    '<Block_star77>': 4,          # Statement*
    '<ContainerMembers_star2>': 3,
    '<ContainerMembers_star3>': 3,
    '<ContainerMembers_star5>': 3,
    '<ParamDeclList_star160>': 3,
    '<AdditionExpr_star66>': 2,
    '<MultiplyExpr_star67>': 2,
    '<BitShiftExpr_star65>': 1,
    '<BitwiseExpr_star64>': 1,
    '<BoolAndExpr_star62>': 1,
    '<BoolOrExpr_star61>': 1,
}


def bound_stars(g):
    """Turn `H -> '' | inner H` into `H -> '' | inner | inner inner | ...`."""
    for name, limit in POST_BOUND.items():
        alts = g.get(name)
        if not alts:
            sys.stderr.write('warning: bound target %s missing\n' % name)
            continue
        rec = [a for a in alts if name in a]
        if not rec:
            sys.stderr.write('warning: %s is not right-recursive\n' % name)
            continue
        inner = [tok for tok in rec[0] if tok != name]
        out = [[]]
        for n in range(1, limit + 1):
            out.append(inner * n)
        g[name] = out
    return g


def apply_tuning(g):
    for rule, alts in POST_REPLACE.items():
        if rule not in g:
            sys.stderr.write('warning: replace target %s missing\n' % rule)
            continue
        g[rule] = [list(a) for a in alts]
    for rule, targets in POST_BIAS.items():
        if rule not in g:
            sys.stderr.write('warning: bias target %s missing\n' % rule)
            continue
        alts = g[rule]
        for alt, n in targets:
            alts = [a for a in alts if a != alt] + [list(alt)] * n
        g[rule] = alts
    return g


def space_terminals(g):
    """Give every punctuation terminal a trailing space.

    The PEG writes operators as `AMPERSAND <- '&' ![=] skip`, so the space
    rides on the `skip` at the end. Dropping the `![=]` predicate took the
    `skip` with it, which left 103 terminals butting straight up against the
    next token. Zig then reads `2 ** f64` as `2 * *f64` -- a binary `*` with a
    space on the left and none on the right -- and AstGen rejects it:
    "binary operator '*' has whitespace on one side, but not the other" was
    131 of ~900 corpus failures, second only to undeclared identifiers.

    Separating every token is always safe in Zig: `a . b`, `* f64` and `. *`
    all parse as their unspaced forms.
    """
    n = 0
    for alts in g.values():
        for alt in alts:
            for i, tok in enumerate(alt):
                if isinstance(tok, str) and tok and not tok.startswith('<') \
                        and not tok.endswith(' '):
                    alt[i] = tok + ' '
                    n += 1
    sys.stderr.write('spaced %d terminals\n' % n)
    return g


def prune(g, root='<Root>'):
    """Drop rules unreachable from the root, and rules that cannot terminate."""
    productive, changed = set(), True
    while changed:
        changed = False
        for k, alts in g.items():
            if k in productive:
                continue
            for a in alts:
                if all(not (t.startswith('<') and t.endswith('>')) or t in productive
                       for t in a):
                    productive.add(k)
                    changed = True
                    break
    for k in list(g):
        g[k] = [a for a in g[k]
                if all(not (t.startswith('<') and t.endswith('>')) or t in productive
                       for t in a)]
        if not g[k]:
            del g[k]
    reach, stack = set(), [root]
    while stack:
        k = stack.pop()
        if k in reach or k not in g:
            continue
        reach.add(k)
        for a in g[k]:
            for t in a:
                if t.startswith('<') and t.endswith('>'):
                    stack.append(t)
    return {k: v for k, v in g.items() if k in reach}


if __name__ == '__main__':
    text = open(sys.argv[1]).read()
    rules, order = parse_grammar(text)
    g = Lowerer(rules).run()
    for name, alts in REPLACE.items():
        g['<%s>' % name] = alts
    g['<START>'] = [['<Root>']]
    g = apply_tuning(g)
    g = bound_stars(g)
    g = space_terminals(g)
    g = prune(g, '<START>')
    json.dump(g, open(sys.argv[2], 'w'), indent=4)
    print('rules: %d  (from %d PEG rules)' % (len(g), len(rules)), file=sys.stderr)
