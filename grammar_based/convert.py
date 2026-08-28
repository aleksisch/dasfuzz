
import re
import sys


def define_PLAIN_TEXT(name, last):
    """Create definition for the PLAIN_TEXT token."""

    print('    "<%s>": [ ["\\\"", "<str_not_escaped>", "\\\""] ],' % name.lower())
    print('    "<str_not_escaped>": [ ["<char>"], ["<char>", "<char>"], ["<char>", "<char>", "<char>"] ],')
    print('    "<char>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"], ["A"], ["B"], ["C"], ["D"], ["E"], ["F"] ]%s' % (',' if not(last) else ''))


def define_IDENTIFIER(name, last):
    """Create definition for the RULE_IDENTIFIER token."""

    print('    "<%s>": [ [ "<id>", "<id>", "<id>", "<idx>" ] ],' % name.lower())
    print('    "<id>": [ ["a"], ["b"], ["c"], ["d"], ["e"], ["f"], ["g"], ["h"], ["i"], ["j"], ["k"], ["l"] ],')
    print('    "<idx>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ]%s' % (',' if not(last) else ''))


def define_SIGNED_INTEGER(name, last):
    """Create definition for the SIGNED_INTEGER token."""

    print('    "<%s>": [ ["-", "<unsigned_integer>"] ]%s' % (name.lower(), ',' if not(last) else ''))


def define_INTEGER(name, last):
    """Create definition for the INTEGER token.

    The lexer's INTEGER is a bare digit run — the sign is unary minus in the
    grammar. Baking a '-' in here made every int literal negative and broke
    every rule that wants a non-negative one (`label N:`, `goto label N`).
    """

    print('    "<%s>": [ ["<fnumber>"], ["<number>", "<fnumber>"], ["<number>", "<fnumber>", "<fnumber>"] ],' % name.lower())
    print('    "<number>": [ ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ],')
    print('    "<fnumber>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ]%s' % (',' if not(last) else ''))


def define_UNSIGNED_INTEGER(name, last):
    """Create definition for the UNSIGNED_INTEGER token."""

    print('    "<%s>": [ ["<fnumber>"], ["<number>", "<fnumber>"], ["<number>", "<fnumber>", "<fnumber>"] ],' % name.lower())
    print('    "<number>": [ ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ],')
    print('    "<fnumber>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ]%s' % (',' if not(last) else ''))

def define_FLOAT(name, last):
    """Create definition for the UNSIGNED_INTEGER token."""

    print('    "<%s>": [ ["<fnumber>", "."], ["<number>", ".", "<fnumber>"], ["<number>", ".", "<fnumber>", "<fnumber>"] ],' % name.lower())
    print('    "<number>": [ ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ],')
    print('    "<fnumber>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ]%s' % (',' if not(last) else ''))


def define_FLOAT16(name, last):
    """Create definition for the DAS_FLOAT16_CONST token (float16 literal, 'h' suffix)."""

    print('    "<%s>": [ ["<number>", ".", "<fnumber>", "h"], ["<number>", "h"], ["<number>", ".", "<fnumber>", "<fnumber>", "h"] ],' % name.lower())
    print('    "<number>": [ ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ],')
    print('    "<fnumber>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ]%s' % (',' if not(last) else ''))


def define_BYTES_ID(name, last):
    """Create definition for the BYTES_ID token."""

    print('    "<%s>": [ ["$"], ["$*"], [ "$", "<id>", "<idx>" ], [ "$", "<id>", "*" ] ],' % name.lower())
    print('    "<id>": [ ["a"], ["b"], ["c"], ["d"], ["e"], ["f"], ["g"], ["h"], ["i"], ["j"], ["k"], ["l"] ],')
    print('    "<idx>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ]%s' % (',' if not(last) else ''))


def define_BYTES_ID_COUNTER(name, last):
    """Create definition for the BYTES_ID_COUNTER token."""

    print('    "<%s>": [ ["#"], ["#*"], [ "#", "<id>", "<idx>" ], [ "#", "<id>", "*" ] ],' % name.lower())
    print('    "<id>": [ ["a"], ["b"], ["c"], ["d"], ["e"], ["f"], ["g"], ["h"], ["i"], ["j"], ["k"], ["l"] ],')
    print('    "<idx>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ]%s' % (',' if not(last) else ''))


def define_BYTES_ID_START(name, last):
    """Create definition for the BYTES_ID_START token."""

    print('    "<%s>": [ ["@"], ["@*"], [ "@", "<id>", "<idx>" ], [ "@", "<id>", "*" ] ],' % name.lower())
    print('    "<id>": [ ["a"], ["b"], ["c"], ["d"], ["e"], ["f"], ["g"], ["h"], ["i"], ["j"], ["k"], ["l"] ],')
    print('    "<idx>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ]%s' % (',' if not(last) else ''))


def define_BYTES_ID_LENGTH(name, last):
    """Create definition for the BYTES_ID_LENGTH token."""

    print('    "<%s>": [ ["!"], ["!*"], [ "!", "<id>", "<idx>" ], [ "!", "<id>", "*" ] ],' % name.lower())
    print('    "<id>": [ ["a"], ["b"], ["c"], ["d"], ["e"], ["f"], ["g"], ["h"], ["i"], ["j"], ["k"], ["l"] ],')
    print('    "<idx>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ]%s' % (',' if not(last) else ''))


def define_BYTES_ID_END(name, last):
    """Create definition for the BYTES_ID_END token."""

    print('    "<%s>": [ ["~"], ["~*"], [ "~", "<id>", "<idx>" ], [ "~", "<id>", "*" ] ],' % name.lower())
    print('    "<id>": [ ["a"], ["b"], ["c"], ["d"], ["e"], ["f"], ["g"], ["h"], ["i"], ["j"], ["k"], ["l"] ],')
    print('    "<idx>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"] ]%s' % (',' if not(last) else ''))


def define_HEX_BYTES(name, last):
    """Create definition for the HEX_BYTES token."""

    print('    "<%s>": [ ["<hex>", "<hex>"] ],' % name.lower())
    print('    "<hex>": [ ["0"], ["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"], ["a"], ["b"], ["c"], ["d"], ["e"], ["f"] ]%s' % (',' if not(last) else ''))


def define_FULL_MASK(name, last):
    """Create definition for the FULL_MASK token."""

    print('    "<%s>": [ ["?", "?"] ]%s' % (name.lower(), ',' if not(last) else ''))


def define_SEMI_MASK(name, last):
    """Create definition for the SEMI_MASK token."""

    print('    "<%s>": [ ["?0"], ["1?"] ]%s' % (name.lower(), ',' if not(last) else ''))


def define_KB(name, last):
    """Create definition for the KB token."""

    print('    "<%s>": [ ["kb"], ["Kb"], ["kB"], ["KB"] ]%s' % (name.lower(), ',' if not(last) else ''))


def define_MB(name, last):
    """Create definition for the MB token."""

    print('    "<%s>": [ ["mb"], ["Mb"], ["mB"], ["MB"] ]%s' % (name.lower(), ',' if not(last) else ''))


def define_GB(name, last):
    """Create definition for the GB token."""

    print('    "<%s>": [ ["gb"], ["Gb"], ["gB"], ["GB"] ]%s' % (name.lower(), ',' if not(last) else ''))

def define_CHAR(name, last):
    print('    "<%s>": [ ["a"], ["b"], ["c"], ["d"], ["e"], ["f"], ["g"], ["h"], ["i"], ["j"], ["k"], ["l"] ],' % (name.lower()))

def define_default(s):
    return lambda x, last: print('    "<%s>": [ [" %s "] ]%s' % (name.lower(), s, ',' if not(last) else ''))

__lexer_tokens = {
    'PLAIN_TEXT': define_PLAIN_TEXT,
    'ESCAPED_TEXT': define_PLAIN_TEXT,
    'RULE_IDENTIFIER': define_IDENTIFIER,
    'INFO_KEY': define_PLAIN_TEXT,
    'SIGNED_INTEGER': define_SIGNED_INTEGER,
    'INTEGER': define_INTEGER,
    'LONG_INTEGER': define_SIGNED_INTEGER,
    'DAS_FLOAT': define_FLOAT,
    'DAS_FLOAT16_CONST': define_FLOAT16,
    'DOUBLE': define_FLOAT,
    'UNSIGNED_INTEGER': define_UNSIGNED_INTEGER,
    'UNSIGNED_LONG_INTEGER': define_UNSIGNED_INTEGER,
    'UNSIGNED_INT8': define_UNSIGNED_INTEGER,

    'BYTES_ID': define_BYTES_ID,
    'BYTES_FUZZY_ID': define_BYTES_ID,
    'BYTES_ID_COUNTER': define_BYTES_ID_COUNTER,
    'BYTES_FUZZY_ID_COUNTER': define_BYTES_ID_COUNTER,
    'BYTES_ID_START': define_BYTES_ID_START,
    'BYTES_FUZZY_ID_START': define_BYTES_ID_START,
    'BYTES_ID_LENGTH': define_BYTES_ID_LENGTH,
    'BYTES_FUZZY_ID_LENGTH': define_BYTES_ID_LENGTH,
    'BYTES_ID_END': define_BYTES_ID_END,
    'BYTES_FUZZY_ID_END': define_BYTES_ID_END,

    "','": lambda x, y: ',',
    "'": lambda x, y: "'",
    "DAS_EMIT_COMMA": define_default('\\n'),
    'NAME': define_IDENTIFIER,
    'HEX_BYTES': define_HEX_BYTES,
    'FULL_MASK': define_FULL_MASK,
    'SEMI_MASK': define_SEMI_MASK,
    'REGEX_BYTES': define_PLAIN_TEXT,
    'REGEX_CLASSES': define_PLAIN_TEXT,
    'REGEX_RANGE': define_PLAIN_TEXT,
    'KB': define_KB,
    'MB': define_MB,
    'GB': define_GB,
    'STRING_CHARACTER'    : define_CHAR,
    'DOUBLE_AT'           : define_default("@@"),
    'AT_FIELD'            : define_default("@field"),
    'NOTAS'               : define_default("!as"),
    'NOTIS'               : define_default("!is"),
    'NOTQAS'              : define_default("!?as"),
    'NOTDOT'              : define_default("!."),
    'NOTQDOT'             : define_default("!?."),
    'NOTBRA'              : define_default("!["),
    'NOTQBRA'             : define_default("!?["),
    'NOTQQ'               : define_default("!??"),

    'DAS_CAPTURE'         : define_default("capture"),
    'DAS_STRUCT'          : define_default("struct"),
    'DAS_CLASS'           : define_default("class"),
    'DAS_LET'             : define_default("let"),
    'DAS_DEF'             : define_default("def"),
    'DAS_WHILE'           : define_default("while"),
    'DAS_IF'              : define_default("if"),
    'DAS_STATIC_IF'       : define_default("static_if"),
    'DAS_ELSE'            : define_default("else"),
    'DAS_FOR'             : define_default("for"),
    'DAS_CATCH'           : define_default("recover"),
    'DAS_TRUE'            : define_default("true"),
    'DAS_FALSE'           : define_default("false"),
    'DAS_NEWT'            : define_default("new"),
    'DAS_TYPEINFO'        : define_default("typeinfo"),
    'DAS_TYPE'            : define_default("type"),
    'DAS_IN'              : define_default("in"),
    'DAS_IS'              : define_default("is"),
    'DAS_AS'              : define_default("as"),
    'DAS_ELIF'            : define_default("elif"),
    'DAS_STATIC_ELIF'     : define_default("static_elif"),
    'DAS_ARRAY'           : define_default("array"),
    'DAS_RETURN'          : define_default("return"),
    'DAS_NULL'            : define_default("null"),
    'DAS_BREAK'           : define_default("break"),
    'DAS_TRY'             : define_default("try"),
    'DAS_OPTIONS'         : define_default("options"),
    'DAS_TABLE'           : define_default("table"),
    'DAS_EXPECT'          : define_default("expect"),
    'DAS_CONST'           : define_default("const"),
    'DAS_REQUIRE'         : define_default("require"),
    'DAS_OPERATOR'        : define_default("operator"),
    'DAS_ENUM'            : define_default("enum"),
    'DAS_FINALLY'         : define_default("finally"),
    'DAS_DELETE'          : define_default("delete"),
    'DAS_DEREF'           : define_default("deref"),
    'DAS_TYPEDEF'         : define_default("typedef"),
    'DAS_TYPEDECL'        : define_default("typedecl"),
    'DAS_WITH'            : define_default("with"),
    'DAS_AKA'             : define_default("aka"),
    'DAS_ASSUME'          : define_default("assume"),
    'DAS_CAST'            : define_default("cast"),
    'DAS_OVERRIDE'        : define_default("override"),
    'DAS_ABSTRACT'        : define_default("abstract"),
    'DAS_UPCAST'          : define_default("upcast"),
    'DAS_ITERATOR'        : define_default("iterator"),
    'DAS_VAR'             : define_default("var"),
    'DAS_ADDR'            : define_default("addr"),
    'DAS_CONTINUE'        : define_default("continue"),
    'DAS_WHERE'           : define_default("where"),
    'DAS_PASS'            : define_default("pass"),
    'DAS_REINTERPRET'     : define_default("reinterpret"),
    'DAS_MODULE'          : define_default("module"),
    'DAS_PUBLIC'          : define_default("public"),
    'DAS_LABEL'           : define_default("label"),
    'DAS_GOTO'            : define_default("goto"),
    'DAS_IMPLICIT'        : define_default("implicit"),
    'DAS_EXPLICIT'        : define_default("explicit"),
    'DAS_SHARED'          : define_default("shared"),
    'DAS_PRIVATE'         : define_default("private"),
    'DAS_SMART_PTR'       : define_default("smart_ptr"),
    'DAS_UNSAFE'          : define_default("unsafe"),
    'DAS_INSCOPE'         : define_default("inscope"),
    'DAS_STATIC'          : define_default("static"),
    'DAS_FIXED_ARRAY'     : define_default("fixed_array"),
    'DAS_DEFAULT'         : define_default("default"),
    'DAS_UNINITIALIZED'   : define_default("uninitialized"),
    'DAS_TBOOL'           : define_default("bool"),
    'DAS_TVOID'           : define_default("void"),
    'DAS_TSTRING'         : define_default("string"),
    'DAS_TAUTO'           : define_default("auto"),
    'DAS_TINT'            : define_default("int"),
    'DAS_TINT2'           : define_default("int2"),
    'DAS_TINT3'           : define_default("int3"),
    'DAS_TINT4'           : define_default("int4"),
    'DAS_TUINT'           : define_default("uint"),
    'DAS_TBITFIELD'       : define_default("bitfield"),
    'DAS_TUINT2'          : define_default("uint2"),
    'DAS_TUINT3'          : define_default("uint3"),
    'DAS_TUINT4'          : define_default("uint4"),
    'DAS_TFLOAT'          : define_default("float"),
    'DAS_TFLOAT2'         : define_default("float2"),
    'DAS_TFLOAT3'         : define_default("float3"),
    'DAS_TFLOAT4'         : define_default("float4"),
    'DAS_TFLOAT16'        : define_default("float16"),
    'DAS_THALF2'          : define_default("half2"),
    'DAS_THALF3'          : define_default("half3"),
    'DAS_THALF4'          : define_default("half4"),
    'DAS_THALF8'          : define_default("half8"),
    'DAS_TSHORT2'         : define_default("short2"),
    'DAS_TSHORT3'         : define_default("short3"),
    'DAS_TSHORT4'         : define_default("short4"),
    'DAS_TSHORT8'         : define_default("short8"),
    'DAS_TUSHORT2'        : define_default("ushort2"),
    'DAS_TUSHORT3'        : define_default("ushort3"),
    'DAS_TUSHORT4'        : define_default("ushort4"),
    'DAS_TUSHORT8'        : define_default("ushort8"),
    'DAS_TBYTE2'          : define_default("byte2"),
    'DAS_TBYTE3'          : define_default("byte3"),
    'DAS_TBYTE4'          : define_default("byte4"),
    'DAS_TBYTE8'          : define_default("byte8"),
    'DAS_TBYTE16'         : define_default("byte16"),
    'DAS_TUBYTE2'         : define_default("ubyte2"),
    'DAS_TUBYTE3'         : define_default("ubyte3"),
    'DAS_TUBYTE4'         : define_default("ubyte4"),
    'DAS_TUBYTE8'         : define_default("ubyte8"),
    'DAS_TUBYTE16'        : define_default("ubyte16"),
    'DAS_TRANGE'          : define_default("range"),
    'DAS_TURANGE'         : define_default("urange"),
    'DAS_TRANGE64'        : define_default("range64"),
    'DAS_TURANGE64'       : define_default("urange64"),
    'DAS_TBLOCK'          : define_default("block"),
    'DAS_TINT64'          : define_default("int64"),
    'DAS_TUINT64'         : define_default("uint64"),
    'DAS_TDOUBLE'         : define_default("double"),
    'DAS_TFUNCTION'       : define_default("function"),
    'DAS_TLAMBDA'         : define_default("lambda"),
    'DAS_TINT8'           : define_default("int8"),
    'DAS_TUINT8'          : define_default("uint8"),
    'DAS_TINT16'          : define_default("int16"),
    'DAS_TUINT16'         : define_default("uint16"),
    'DAS_TTUPLE'          : define_default("tuple"),
    'DAS_TVARIANT'        : define_default("variant"),
    'DAS_GENERATOR'       : define_default("generator"),
    'DAS_YIELD'           : define_default("yield"),
    'DAS_SEALED'          : define_default("sealed"),
    'DAS_TEMPLATE'        : define_default("template"),
    'STRING_CHARACTER_ESC': define_default("\\\\"),
    'BEGIN_STRING'        : define_default('\\"'),
    'END_STRING'          : define_default('\\"'),
    'ADDEQU'              : define_default("+="),
    'SUBEQU'              : define_default("-="),
    'DIVEQU'              : define_default("/="),
    'MULEQU'              : define_default("*="),
    'MODEQU'              : define_default("%="),
    'ANDEQU'              : define_default("&="),
    'OREQU'               : define_default("|="),
    'XOREQU'              : define_default("^="),
    'SHL'                 : define_default("<<"),
    'SHR'                 : define_default(">>"),
    'ADDADD'              : define_default("++"),
    'SUBSUB'              : define_default("--"),
    'LEEQU'               : define_default("<="),
    'SHLEQU'              : define_default("<<="),
    'SHREQU'              : define_default(">>="),
    'GREQU'               : define_default(">="),
    'EQUEQU'              : define_default("=="),
    'NOTEQU'              : define_default("!="),
    'RARROW'              : define_default("->"),
    'LARROW'              : define_default("<-"),
    'PRE_DEC'              : define_default("--"),
    'PRE_INC'              : define_default("++"),
    'POST_DEC'              : define_default("--"),
    'POST_INC'              : define_default("++"),
    'DEREF'              : define_default("*"),
    'QQ'                  : define_default("??"),
    "'$'"                   : lambda x, y: "$",
    "'#'"                   : lambda x, y: "#",
    "'!'"                   : lambda x, y: "!",
    "':'"                   : lambda x, y: ":",
    "'='"                   : lambda x, y: "=",
    "'['"                   : lambda x, y: "[",
    "']'"                   : lambda x, y: "]",
    "'+'"                   : lambda x, y: "+",
    "'-'"                   : lambda x, y: "-",
    "'*'"                   : lambda x, y: "*",
    "'<'"                   : lambda x, y: "<",
    "'>'"                   : lambda x, y: ">",
    "'<='"                   : lambda x, y: "<=",
    "'>='"                   : lambda x, y: ">=",
    "'&'"                   : lambda x, y: "&",
    "'^'"                   : lambda x, y: "^",
    "'^^'"                   : lambda x, y: "^^",
    "'?'"                   : lambda x, y: "?",
    "UNARY_PLUS"            : lambda x, y: "+",
    "UNARY_MINUS"            : lambda x, y: "-",
    "'&&'"                   : lambda x, y: "&&",
    "'~'"                   : lambda x, y: "~",
    "'@'"                   : lambda x, y: "@",
    "'.'"                   : lambda x, y: ".",
    "'('"                   : lambda x, y: "(",
    "')'"                   : lambda x, y: ")",
    "''"                   : lambda x, y: "",
    "'/'"                   : lambda x, y: "/",
    ":"                   : lambda x, y: ":",
    "'%'"                   : lambda x, y: "%",
    "DAS_EMIT_SEMICOLON"                   : define_default("\\n"),
    "BEGIN_STRING_EXPR"                   : define_default("{"),
    "END_STRING_EXPR"                   : define_default("}"),
    'QDOT'                : define_default("?."),
    'QBRA'                : define_default("?["),
    'LPIPE'               : define_default("<|"),
    'RPIPE'               : define_default("|>"),
    'CLONEEQU'            : define_default(":="),
    'ROTL'                : define_default("<<<"),
    'ROTR'                : define_default(">>>"),
    'ROTLEQU'             : define_default("<<<="),
    'ROTREQU'             : define_default(">>>="),
    'MAPTO'               : define_default("=>"),
    'COLCOL'              : define_default("::"),
    'ANDAND'              : define_default("&&"),
    'OROR'                : define_default("||"),
    'XORXOR'              : define_default("^^"),
    'ANDANDEQU'           : define_default("&&="),
    'OROREQU'             : define_default("||="),
    'XORXOREQU'           : define_default("^^="),
    'DOTDOT'              : define_default(".."),
    'MTAG_E'              : define_default("$$"),
    'MTAG_I'              : define_default("$i"),
    'MTAG_V'              : define_default("$v"),
    'MTAG_B'              : define_default("$b"),
    'MTAG_A'              : define_default("$a"),
    'MTAG_T'              : define_default("$t"),
    'MTAG_C'              : define_default("$c"),
    'MTAG_F'              : define_default("$f"),
    'MTAG_DOTDOTDOT'      : define_default("..."),
}


# ---------------------------------------------------------------------------
# UnitTest extras + bias.
#
# When this script is re-run on the .ypp source, the resulting JSON should
# already include the UnitTest C++ binding surface plus a weight bias toward
# those constructs (so the AFL Grammar-Mutator picks them often enough to
# stress the bindings). Rather than hand-editing the generated JSON, the
# additions and weights live here and are applied uniformly by every run.
#
# Tokens follow the same wire format as the rest of the tree: each token is
# the literal JSON text (a quoted nonterminal reference like `"<expr>"` or
# a quoted literal like `" TestObjectFoo "`). The helpers below build that.
# ---------------------------------------------------------------------------

def _NT(name):
    """A reference to a nonterminal."""
    return '"<%s>"' % name

def _LIT(text):
    """A literal that should be emitted verbatim in fuzzed output."""
    return '"%s"' % text.replace('\\', '\\\\').replace('"', '\\"')


# New non-terminals to inject after parsing.
UNIT_TEST_RULES = {
    'unit_test_require': [[_LIT('require UnitTest;\n')]],
    'unit_test_type': [
        [_LIT(' TestObjectFoo ')],   [_LIT(' TestObjectBar ')],
        [_LIT(' TestObjectSmart ')], [_LIT(' TestObjectNotLocal ')],
        [_LIT(' TestObjectNotNullPtr ')], [_LIT(' FancyClass ')],
        [_LIT(' SomeDummyType ')],   [_LIT(' Point3 ')], [_LIT(' Point3Array ')],
        [_LIT(' FooArray ')],        [_LIT(' ByteCode ')],
        [_LIT(' BigEntityId ')],     [_LIT(' EntityId ')],
        [_LIT(' SceneNodeId ')],     [_LIT(' SampleVariant ')],
    ],
    'unit_test_enum_type': [
        [_LIT(' SomeEnum ')], [_LIT(' SomeEnum98 ')], [_LIT(' SomeEnum_16 ')],
        [_LIT(' GooEnum ')],  [_LIT(' GooEnum98 ')],  [_LIT(' OpCode ')],
    ],
    'unit_test_enum': [
        [_LIT(' SomeEnum.zero ')], [_LIT(' SomeEnum.one ')], [_LIT(' SomeEnum.two ')],
        [_LIT(' SomeEnum98.zero ')], [_LIT(' SomeEnum98.one ')], [_LIT(' SomeEnum98.two ')],
        [_LIT(' SomeEnum_16.zero ')], [_LIT(' SomeEnum_16.one ')], [_LIT(' SomeEnum_16.two ')],
        [_LIT(' GooEnum.regular ')], [_LIT(' GooEnum.hazardous ')],
        [_LIT(' GooEnum98.soft ')],  [_LIT(' GooEnum98.hard ')],
        [_LIT(' OpCode.op_nop ')], [_LIT(' OpCode.op_mov_a_arg ')],
        [_LIT(' OpCode.op_mov_arg_b ')], [_LIT(' OpCode.op_dec_a ')],
        [_LIT(' OpCode.op_cmple_a_low_zx ')], [_LIT(' OpCode.op_cjmp ')],
        [_LIT(' OpCode.op_mov_c_a ')], [_LIT(' OpCode.op_mov_a_low_zx ')],
        [_LIT(' OpCode.op_mov_b_low_zx ')], [_LIT(' OpCode.op_xchange_a_b ')],
        [_LIT(' OpCode.op_add_b_a ')], [_LIT(' OpCode.op_loop ')],
        [_LIT(' OpCode.op_return_b ')],
    ],
    'unit_test_constant': [[_LIT(' UNIT_TEST_CONSTANT ')]],
    # Boolean-producing expressions for condition slots. The generic <expr>
    # rule is ~90% numeric `int const`, so `if (5)` / `while (3)` / `assert(2)`
    # constantly failed "condition must be boolean". <expr_bool> is wired into
    # every condition slot (see REPLACE_RULES) so conditions are always well
    # typed.
    'expr_bool': [
        [_NT('das_true')],
        [_NT('das_false')],
        [_LIT('('), _NT('expr_numeric_const'), _LIT(' == '), _NT('expr_numeric_const'), _LIT(')')],
        [_LIT('('), _NT('expr_numeric_const'), _LIT(' != '), _NT('expr_numeric_const'), _LIT(')')],
        [_LIT('('), _NT('expr_numeric_const'), _LIT(' < '),  _NT('expr_numeric_const'), _LIT(')')],
        [_LIT('('), _NT('expr_numeric_const'), _LIT(' > '),  _NT('expr_numeric_const'), _LIT(')')],
        [_LIT('('), _NT('expr_numeric_const'), _LIT(' <= '), _NT('expr_numeric_const'), _LIT(')')],
        [_LIT('('), _NT('expr_numeric_const'), _LIT(' >= '), _NT('expr_numeric_const'), _LIT(')')],
        [_LIT('(!'), _NT('expr_bool'), _LIT(')')],
        [_LIT('('), _NT('expr_bool'), _LIT(' && '), _NT('expr_bool'), _LIT(')')],
        [_LIT('('), _NT('expr_bool'), _LIT(' || '), _NT('expr_bool'), _LIT(')')],
    ],
    # Valid `options` names (a curated subset of real daslang bool options).
    # The grammar's generic `options <name>` emitted arbitrary names like
    # `options var3`, all rejected with "invalid option". Restricting the
    # name to real options (see options_decl in REPLACE_RULES) kills that
    # whole error bucket.
    'unit_test_option': [
        [_LIT('indenting')], [_LIT('no_aot')], [_LIT('rtti')],
        [_LIT('optimize')], [_LIT('persistent_heap')],
        [_LIT('no_global_variables')], [_LIT('unsafe_table_lookup')],
        [_LIT('strict_smart_pointers')], [_LIT('no_unused_function_arguments')],
        [_LIT('no_unused_block_arguments')], [_LIT('remove_unused_symbols')],
    ],
    # ---------------------------------------------------------------------
    # New AOT-codegen-heavy statement families.
    #
    # The bugs found so far are all AOT C++ codegen defects, but whole
    # feature areas were never emitted by the old bias. These add the ones
    # with the most back-end surface that the grammar previously ignored:
    # closures/captures (closure-struct codegen) and generators/iterators
    # (coroutine state machine). Container clone (`:=`) exercises the
    # generated clone/finalize helpers.
    #
    # Every form is fully self-contained — it declares whatever it needs
    # inside its own scope and refers to no external/hardcoded decl, so no
    # prelude is required and the program reaches AOT instead of dying in
    # typecheck. All forms validated against daslang -aot.
    # ---------------------------------------------------------------------
    # Invoked closures/lambdas — exercise closure-struct + capture codegen.
    'unit_test_stmt_closure': [
        [_LIT(' invoke($() {\n'), _NT('expression_any_nonempty'), _LIT('}) ;\n')],
        [_LIT(' invoke($( '), _NT('name'), _LIT(':int ) {\n'),
         _NT('expression_any_nonempty'), _LIT('}, '), _NT('expr_numeric_const'), _LIT(') ;\n')],
        # Move-capture lambda, self-contained in a bare block so the fixed
        # capture var name never collides across repeats.
        [_LIT(' { var cv = 0 ;\n invoke(@ capture(<- cv)( cx:int ){ cv += cx; }, '),
         _NT('expr_numeric_const'), _LIT(') ;\n }\n')],
    ],
    # Inline generator/iterator consumption — coroutine state-machine codegen.
    # The generator is built inline, so nothing external is referenced.
    'unit_test_stmt_geniter': [
        [_LIT(' for ( ge in generator<int>() <| $() { yield '),
         _NT('expr_numeric_const'), _LIT('; yield '), _NT('expr_numeric_const'),
         _LIT('; return false; } ) {\n'), _NT('expression_any_nonempty'), _LIT('}\n')],
    ],
    # Container clone (`:=`) — generated clone/finalize helpers. Self-contained
    # bare block; fixed names scoped to the block so repeats never collide.
    'unit_test_stmt_clone': [
        [_LIT(' { var ca : array<int>; var cb : array<int>; cb := ca; }\n')],
        [_LIT(' { var ta : table<int;int>; var tb : table<int;int>; tb := ta; }\n')],
    ],
    # Wire the new statement forms into the generic statement rule so they
    # appear in main() and every function body. Added here (not via BIAS)
    # because <expression_any_nonempty> is derived from <expression_any>
    # before BIAS runs — these must exist on the rule first. BIAS then sets
    # their weights.
    'expression_any': [
        [_NT('unit_test_stmt_closure')],
        [_NT('unit_test_stmt_geniter')],
        [_NT('unit_test_stmt_clone')],
        # `debug(expr)` is a real builtin the grammar never emitted, which left
        # InferTypes::visit(ExprDebug*) at 0% coverage.
        [_LIT(' debug ('), _NT('expr'), _LIT(');\n')],
    ],
    # Calls into the C++ binding surface from modules/dasUnitTest/test_handles.cpp.
    'unit_test_call': [
        [_LIT(' testFoo ('), _NT('expr'), _LIT(')')],
        [_LIT(' set_foo_data ('), _NT('expr'), _LIT(','), _NT('expr'), _LIT(')')],
        [_LIT(' testAdd ('), _NT('expr'), _LIT(','), _NT('expr'), _LIT(')')],
        [_LIT(' getSamplePoint3 ()')],
        [_LIT(' doubleSamplePoint3 ('), _NT('expr'), _LIT(')')],
        [_LIT(' project_to_nearest_navmesh_point ('), _NT('expr'), _LIT(','), _NT('expr'), _LIT(')')],
        [_LIT(' makeDummy ()')],
        [_LIT(' takeDummy ('), _NT('expr'), _LIT(')')],
        [_LIT(' makeTestObjectSmart ()')],
        [_LIT(' countTestObjectSmart ('), _NT('expr'), _LIT(')')],
        [_LIT(' getTotalTestObjectSmart ()')],
        [_LIT(' fooPtr2Ref ('), _NT('expr'), _LIT(')')],
        [_LIT(' getPtr ()')],
        [_LIT(' makeSampleI ()')],
        [_LIT(' makeSampleF ()')],
        [_LIT(' makeSampleS ()')],
        [_LIT(' evalByteCode ('), _NT('expr'), _LIT(')')],
        [_LIT(' test_abi_mad ('), _NT('expr'), _LIT(','), _NT('expr'), _LIT(','), _NT('expr'), _LIT(')')],
        [_LIT(' testGetDiv ('), _NT('expr'), _LIT(','), _NT('expr'), _LIT(')')],
        [_LIT(' testGetNan ()')],
        [_LIT(' test_das_string ('), _NT('expr_full_block'), _LIT(')')],
        [_LIT(' printw ('), _NT('expr'), _LIT(')')],
        [_LIT(' hit_me ('), _NT('expr'), _LIT(','), _NT('expr'), _LIT(','), _NT('expr'), _LIT(')')],
        [_LIT(' efn_flip ('), _NT('expr'), _LIT(')')],
        [_LIT(' efn_takeOne_giveTwo ('), _NT('expr'), _LIT(')')],
        [_LIT(' efn_takeOne_giveTwo_98 ('), _NT('expr'), _LIT(')')],
        [_LIT(' make_invalid_id ()')],
        [_LIT(' CppS1Size ()')],
        [_LIT(' CppS2Size ()')],
        [_LIT(' CppS2DOffset ()')],
        [_LIT(' testPoint3Array ('), _NT('expr'), _LIT(','), _NT('expr_full_block'), _LIT(')')],
        [_LIT(' testFooArray ('), _NT('expr'), _LIT(','), _NT('expr_full_block'), _LIT(')')],
        [_LIT(' testCMRES ()')],
    ],
}


# Weight bias: rule_name -> [(alt, total_count_after_normalisation)].
# Idempotent: each run normalises the count of the targeted alt to exactly
# this value, regardless of how many copies were present before.
BIAS = {
    'expr': [
        ([_NT('unit_test_call')],     12),
        ([_NT('unit_test_enum')],      6),
        ([_NT('unit_test_constant')],  3),
    ],
    'expression_any': [
        ([_NT('unit_test_call'), _LIT(';\n')], 6),
        # New AOT-codegen-heavy constructs (see UNIT_TEST_RULES). Weighted so
        # a meaningful share of statements exercise closures / generators /
        # clone without drowning the rest.
        ([_NT('unit_test_stmt_closure')], 5),
        ([_NT('unit_test_stmt_geniter')], 4),
        ([_NT('unit_test_stmt_clone')],   3),
    ],
    'name_in_namespace': [
        ([_NT('unit_test_type')], 6),
    ],
    'basic_type_declaration': [
        ([_NT('unit_test_type')], 4),
    ],
    'expr_call': [
        ([_NT('unit_test_call')], 6),
    ],
    # typeinfo is reachable but the generator almost never picks it: the rule is
    # expensive next to the cheap leaves of <expr_no_bracket>, so 0 of 500 seeds
    # contained one. Weight it up -- InferTypes::visit(ExprTypeInfo*) is 587
    # lines at 42.8%, the coldest function in type inference.
    'expr_no_bracket': [
        ([_NT('expr_type_info')], 40),
    ],
}


# Alternatives that empirically generate noise (compile errors that don't
# exercise interesting compiler paths). Each entry is a list of token
# strings; every matching alt is dropped from the rule. Tightening the
# grammar here cuts the share of pure-typecheck-noise inputs and gives the
# fuzzer more cycles on shapes that actually reach the back end.
REMOVE_ALTS = {
    # Module decl can only appear as the very first declaration; it's
    # re-introduced as a START prologue variant below. Generic
    # `require <name>` always fails because <name> resolves to
    # var1/var2/var3, none of which are real modules — keep only the
    # UnitTest alt of <require_decl>. Typedef/expect are still allowed
    # at program scope (REPLACE_RULES gives them a terminator).
    'program': [
        [_NT('program'), _NT('module_decl')],
        [_NT('program'), _NT('require_decl')],
    ],
    # Enum *type* names (GooEnum, OpCode, …) shouldn't appear as bare value
    # expressions. <unit_test_enum> already covers `EnumName.value` form,
    # which is the only correct form.
    'name_in_namespace': [
        [_NT('unit_test_enum_type')],
    ],
    # Stale alts from earlier convert.py iterations that emitted a literal
    # `\n` (backslash + n) instead of a real newline — the daslang lexer
    # rejects the backslash as an invalid token.
    'unit_test_require': [
        [_LIT('require UnitTest\\n')],
    ],
    'expression_any': [
        [_NT('unit_test_call'), _LIT(';\\n')],
    ],
    # Bare `;` inside struct body is rejected — parser needs a field/method
    # declaration. Function prototypes (`def name;` without a body) are
    # also rejected by ds2 in struct contexts.
    'struct_variable_declaration_list': [
        [_NT('struct_variable_declaration_list'), _NT('das_emit_semicolon')],
        [_NT('struct_variable_declaration_list'), _NT('das_def'),
         _NT('optional_constant'), _NT('function_declaration_header'), _LIT(';\n')],
    ],
}


# Fresh top-level alts for <START>: emit `module` / `require UnitTest` /
# `options` lines once, before any other declarations. Avoids the
# "module name has to be first" error and ensures UnitTest is reachable
# without polluting the recursive <program> rule.
START_PROLOGUE = [
    # Default — most fuzz inputs start with require UnitTest only.
    [_NT('unit_test_require'), _NT('program'), _NT('global_main_declaration')],
    # Some inputs declare a module first (must precede any other decl).
    [_NT('module_decl'), _NT('unit_test_require'),
     _NT('program'), _NT('global_main_declaration')],
]


# Whole-rule replacements. Whatever was previously defined for these names is
# discarded; the value below becomes the rule. Useful for fixing rules whose
# default form encodes a wrong literal (e.g. an `[export]` baked into every
# `def`, which is invalid inside struct/class bodies).
REPLACE_RULES = {
    # Table keys must be a basic hashable type. The generic <type_declaration>
    # yields `auto` / arrays / blocks, which is the single biggest compile-rate
    # killer: "table key has to be declared as a basic 'hashable' type".
    'table_type_pair': [
        [_NT('table_key_type')],
        [_NT('table_key_type'), _NT('c_or_s'), _NT('type_declaration')],
    ],
    # An empty `{}` table literal infers key type `auto`, which is not
    # hashable -- the top compile-rate killer once table<K> was fixed. Force at
    # least one `key => value` pair so the key type can be inferred.
    'make_table_decl': [
        [_LIT('{'), _NT('push_table_nesting'), _NT('table_entry_list'), _LIT('}')],
    ],
    'table_entry_list': [
        [_NT('expr'), _NT('mapto'), _NT('expr')],
        [_NT('table_entry_list'), _LIT(','), _NT('expr'), _NT('mapto'), _NT('expr')],
    ],
    # typeinfo's trait name came from <name_in_namespace> (var1..var64), so
    # every `typeinfo varN(x)` was rejected as an unknown trait and the 85 real
    # trait branches in InferTypes::visit(ExprTypeInfo*) -- 587 lines, the
    # coldest function in type inference -- were never reached. These 71
    # are the traits verified to compile with a simple expression argument.
    'typeinfo_trait': [
        [_LIT('alignof')], [_LIT('builtin_module_exists')], [_LIT('can_be_placed_in_container')], [_LIT('can_clone')], [_LIT('can_clone_from_const')], [_LIT('can_copy')], [_LIT('can_delete')], [_LIT('can_delete_ptr')], [_LIT('can_move')], [_LIT('can_new')], [_LIT('fulltypename')], [_LIT('has_nontrivial_copy')], [_LIT('has_nontrivial_ctor')], [_LIT('has_nontrivial_dtor')], [_LIT('is_any_vector')], [_LIT('is_argument')], [_LIT('is_array')], [_LIT('is_bitfield')], [_LIT('is_class')], [_LIT('is_const')], [_LIT('is_dim')], [_LIT('is_distinct')], [_LIT('is_double')], [_LIT('is_enum')], [_LIT('is_float')], [_LIT('is_function')], [_LIT('is_handle')], [_LIT('is_int')], [_LIT('is_int64')], [_LIT('is_iterable')], [_LIT('is_iterator')], [_LIT('is_lambda')], [_LIT('is_local')], [_LIT('is_numeric')], [_LIT('is_numeric_comparable')], [_LIT('is_pod')], [_LIT('is_pod_delete')], [_LIT('is_pointer')], [_LIT('is_raw')], [_LIT('is_ref')], [_LIT('is_ref_type')], [_LIT('is_ref_value')], [_LIT('is_safe_to_delete')], [_LIT('is_smart_ptr')], [_LIT('is_string')], [_LIT('is_struct')], [_LIT('is_table')], [_LIT('is_temp')], [_LIT('is_temp_type')], [_LIT('is_tuple')], [_LIT('is_unsafe_when_uninitialized')], [_LIT('is_variant')], [_LIT('is_vector')], [_LIT('is_void')], [_LIT('is_void_pointer')], [_LIT('is_workhorse')], [_LIT('modulename')], [_LIT('need_delete')], [_LIT('need_inscope')], [_LIT('needs_container_finalize')], [_LIT('needs_container_init')], [_LIT('needs_nontrivial_init')], [_LIT('safe_has_field')], [_LIT('safe_variant_index')], [_LIT('sizeof')], [_LIT('stripped_typename')], [_LIT('struct_safe_has_annotation')], [_LIT('struct_safe_has_annotation_argument')], [_LIT('typename')], [_LIT('undecorated_typename')], [_LIT('vector_dim')],
    ],
    'expr_type_info': [
        [_NT('das_typeinfo'), _NT('typeinfo_trait'), _LIT('('), _NT('expr'), _LIT(')')],
        [_NT('das_typeinfo'), _NT('typeinfo_trait'), _LIT('<'), _NT('name'), _LIT('>'), _LIT('('), _NT('expr'), _LIT(')')],
    ],
    'table_key_type': [
        [_LIT('int')], [_LIT('uint')], [_LIT('int64')],
        [_LIT('uint64')], [_LIT('string')],
    ],
    # Annotation names came from <name_in_namespace> (var1..var64), so every
    # annotation was "annotation varN is not found". Use names that actually
    # exist; all of these verified to compile on both functions and structs.
    'annotation_declaration_name': [
        [_LIT('export')], [_LIT('sideeffects')], [_LIT('unsafe_operation')],
        [_LIT('no_aot')], [_LIT('deprecated')], [_LIT('hybrid')],
        [_LIT('unused_argument')], [_LIT('generic')], [_LIT('init')],
        [_LIT('finalize')], [_LIT('jit')],
    ],
    'program': [
        [_NT('structure_declaration')],
        [_NT('enum_declaration')],
        [_NT('global_let')],
        [_NT('global_function_declaration')],
        [_NT('variant_alias_declaration')],
        [_NT('tuple_alias_declaration')],
        [_NT('bitfield_alias_declaration')],
        [_NT('options_decl')],
        [_NT('program'), _NT('structure_declaration')],
        [_NT('program'), _NT('enum_declaration')],
        [_NT('program'), _NT('global_let')],
        [_NT('program'), _NT('global_function_declaration')],
        [_NT('program'), _NT('variant_alias_declaration')],
        [_NT('program'), _NT('tuple_alias_declaration')],
        [_NT('program'), _NT('bitfield_alias_declaration')],
        [_NT('program'), _NT('options_decl')],
    ],
    # Condition slots: draw from <expr_bool> (see UNIT_TEST_RULES) instead of
    # the numeric-heavy generic <expr>, so if / while / assert / elif and the
    # break-if / continue-if guards type-check.
    'expression_if_then_else': [
        [_NT('if_or_static_if'), _LIT('('), _NT('expr_bool'), _LIT(')'),
         _NT('expression_if_block'), _NT('expression_else')],
    ],
    'expression_while_loop': [
        [_NT('das_while'), _LIT('('), _NT('expr_bool'), _LIT(')'), _NT('expression_block')],
    ],
    'expression_assert': [
        [_NT('das_assert'), _LIT('('), _NT('expr_bool'), _LIT(')')],
        [_NT('das_verify'), _LIT('('), _NT('expr_bool'), _LIT(')')],
        [_NT('das_panic'), _LIT('('), _NT('string_builder'), _LIT(')')],
    ],
    'expression_else': [
        [_LIT('\n')],
        [_NT('das_else'), _NT('expression_else_block'), _LIT('\n')],
        [_NT('elif_or_static_elif'), _LIT('('), _NT('expr_bool'), _LIT(')'),
         _NT('expression_else_block'), _NT('expression_else')],
    ],
    'expression_if_then_else_oneliner': [
        [_NT('expression_if_one_liner'), _NT('das_if'), _LIT('('), _NT('expr_bool'), _LIT(')'),
         _NT('expression_else_one_liner'), _LIT(';\n')],
    ],
    'expression_break': [
        [_NT('das_break'), _LIT(';\n')],
        [_NT('das_break'), _NT('das_if'), _LIT('('), _NT('expr_bool'), _LIT(')'), _LIT(';\n')],
    ],
    'expression_continue': [
        [_NT('das_continue'), _LIT(';\n')],
        [_NT('das_continue'), _NT('das_if'), _LIT('('), _NT('expr_bool'), _LIT(')'), _LIT(';\n')],
    ],
    'das_def': [[_LIT(' def ')]],
    # Top-level annotated `def`. Only valid for global functions.
    'das_export_def': [[_LIT('\n[export]\ndef ')]],
    # Global function decls take the export form.
    'global_function_declaration': [[_NT('das_export_def'), _NT('function_declaration')]],
    # main() is a global function; same export prefix.
    # Earlier versions embedded a `print("OOOOOO{<expr>}")` here as a marker,
    # but format-string `{` / `}` collide with `{` / `}` produced inside the
    # generated expression (table literals, blocks) and create spurious
    # syntax errors.
    # Body is always at least one non-empty statement — `def main {}` and
    # `def main { ; }` waste a fuzz run since the rest of the grammar
    # never gets exercised. <expression_any_nonempty> is derived from
    # <expression_any> in apply_extras_and_bias() by filtering out the
    # bare `;\n` alt.
    'global_main_declaration': [[
        _NT('das_export_def'), _LIT('main'),
        _LIT('{\n'),
        _NT('expression_any_nonempty'),
        _NT('expressions'),
        _LIT('}'),
        _NT('expression_block_finally'),
    ]],
    # ds2 syntax is `class template Foo {}` / `struct template Foo {}` —
    # the keyword order in the original grammar (`template class`) is wrong
    # and produces "unexpected template, expecting struct or class".
    'class_or_struct': [
        [_NT('das_class')],
        [_NT('das_struct')],
        [_NT('das_class'), _NT('das_template')],
        [_NT('das_struct'), _NT('das_template')],
    ],
    # Top-level facts must end with a newline / semicolon. Without a
    # terminator the parser keeps consuming tokens from the next line and
    # then errors on whatever follows ("unexpected '(' expecting newline").
    'module_decl': [
        [_NT('das_module'), _NT('name'), _LIT(';\n')],
        [_NT('das_module'), _NT('name'), _NT('das_public'),  _LIT(';\n')],
        [_NT('das_module'), _NT('name'), _NT('das_private'), _LIT(';\n')],
    ],
    'require_decl': [
        [_NT('das_require'), _LIT(' UnitTest '), _LIT(';\n')],
    ],
    # ds2 `options` only accepts an annotation_argument_list (name=value
    # pairs where value is a literal — no expressions, no calls).
    'options_decl': [
        [_NT('das_options'), _NT('unit_test_option'), _LIT(' = '), _NT('das_true'),  _LIT(';\n')],
        [_NT('das_options'), _NT('unit_test_option'), _LIT(' = '), _NT('das_false'), _LIT(';\n')],
    ],
    # Capture entries: keep only real capture modes (&, =, <-, := / clone).
    # The original grammar's `<name> ( <name> )` alt produced `var6(var3)`,
    # rejected with "unknown capture mode".
    'capture_entry': [
        [_LIT('&'), _NT('name')],
        [_LIT('='), _NT('name')],
        [_NT('larrow'), _NT('name')],
        [_NT('cloneequ'), _NT('name')],
    ],
    # Enum / bitfield bodies must not start with a comma — split into a
    # non-empty list helper so leading-comma forms become unreachable.
    'enum_list': [
        [],
        [_NT('enum_list_nonempty')],
    ],
    'enum_list_nonempty': [
        [_NT('enum_expression')],
        [_NT('enum_list_nonempty'), _NT('commas'), _NT('enum_expression')],
    ],
    'bitfield_alias_bits': [
        [],
        [_NT('bitfield_alias_bits_nonempty')],
    ],
    'bitfield_alias_bits_nonempty': [
        [_NT('name')],
        [_NT('bitfield_alias_bits_nonempty'), _NT('commas'), _NT('name')],
    ],
    'typedef_decl': [
        [_NT('das_typedef'), _NT('name'), _LIT(' = '),
         _NT('type_declaration_no_options'), _LIT(';\n')],
    ],
    'expect_decl': [
        [_NT('das_expect'), _NT('name'),
         _NT('begin_string'), _NT('character_sequence'), _NT('end_string'),
         _LIT(';\n')],
    ],
    # Add spaces around `=` / `<-` so a trailing type modifier like `&` does
    # not lex-merge with a following `=` into `&=` (causing the
    # "unexpected &= expecting <- or := or '='" error).
    'copy_or_move': [
        [_LIT(' = ')],
        [_NT('larrow')],
    ],
    'copy_or_move_or_clone': [
        [_LIT(' = ')],
        [_NT('larrow')],
        [_NT('cloneequ')],
    ],
}


# The original <name> rule had only 8 alternatives (var1..var8), so any
# program declaring more than a few aliases / globals / enums / function
# args collided constantly ("type alias is already defined", "global
# variable is already declared", ...). A larger pool makes redeclaration
# collisions rare without otherwise changing behaviour (bare-name value
# references are not a significant share of generated exprs).
REPLACE_RULES['name'] = [[_LIT('var%d' % i)] for i in range(1, 65)]


def prune_dangling(tree):
    """Drop alternatives that reference a non-terminal nothing defines.

    Upstream grammar changes retire constructs (e.g. `assert` stopped being a
    keyword), which leaves REPLACE_RULES / UNIT_TEST_RULES entries pointing at
    names that no longer exist. Emitting them verbatim would inject literal
    "<das_assert>" text into every generated program, so prune to a fixpoint.
    """

    def refs(alt):
        return [t for t in alt
                if t.startswith('"<') and t.endswith('>"')]

    # Token non-terminals (<das_tint>, <shl>, ...) are not part of `tree` —
    # they are emitted after it from __lexer_tokens. Count them as defined.
    tokens = set('"<%s>"' % k.lower() for k in __lexer_tokens)

    while True:
        defined = set('"<%s>"' % k for k in tree) | tokens
        dropped = False

        for k in list(tree):
            kept = [a for a in tree[k] if all(t in defined for t in refs(a))]
            if len(kept) != len(tree[k]):
                dropped = True
                if kept:
                    tree[k] = kept
                else:
                    del tree[k]

        if not dropped:
            return tree


def apply_extras_and_bias(tree):
    """Inject UnitTest non-terminals and re-weight key rules.

    Mutates and returns ``tree`` in-place.
    """
    # Replace whole rules first (overrides anything previously set).
    for name, alts in REPLACE_RULES.items():
        tree[name] = list(alts)
    # Add new rules (or extend if already present).
    for name, alts in UNIT_TEST_RULES.items():
        existing = tree.get(name, [])
        for alt in alts:
            if alt not in existing:
                existing.append(alt)
        tree[name] = existing
    # Drop noisy alts.
    for rule, drop in REMOVE_ALTS.items():
        alts = tree.get(rule)
        if alts is None:
            sys.stderr.write("warning: remove rule %r missing in grammar\n" % rule)
            continue
        tree[rule] = [a for a in alts if a not in drop]
    # Derive <expression_any_nonempty> from <expression_any> by stripping
    # the empty-statement alt. Used by <global_main_declaration> to force
    # at least one real statement in the body.
    ea = tree.get('expression_any')
    if ea is not None:
        empty_stmt = [_LIT(';\n')]
        tree['expression_any_nonempty'] = [a for a in ea if a != empty_stmt]
    # Re-weight target alternatives.
    for rule, targets in BIAS.items():
        alts = tree.get(rule)
        if alts is None:
            sys.stderr.write("warning: bias rule %r missing in grammar\n" % rule)
            continue
        for alt, desired in targets:
            kept = [a for a in alts if a != alt]
            alts = kept + ([alt] * desired)
        tree[rule] = alts
    return prune_dangling(tree)


def apply_to_json(path):
    """Apply extras / removals / bias to an already-generated JSON in place.

    Useful when the active grammar is not regenerated from a .ypp on every
    edit but we still want one source of truth for these transforms.
    """
    import json
    with open(path, 'r') as f:
        data = json.load(f, strict=False)
    # Tokens in a JSON-encoded grammar are bare strings ('<expr>', ' foo ').
    # The transforms in this module use the raw "<expr>" / "\" foo \"" form
    # used at parse time — convert both directions.
    def to_raw(tok):
        if tok.startswith('<') and tok.endswith('>'):
            return _NT(tok[1:-1])
        return _LIT(tok.replace('\\', '\\\\').replace('"', '\\"')) if False else '"%s"' % tok.replace('\\', '\\\\').replace('"', '\\"')
    def from_raw(tok):
        # raw is `"<x>"` or `"literal"` — strip outer quotes and unescape.
        assert tok.startswith('"') and tok.endswith('"')
        s = tok[1:-1]
        return s.replace('\\"', '"').replace('\\\\', '\\')
    raw = {}
    for rule, alts in data.items():
        # data keys are strings like "<rule>"; strip wrappers for our tree shape.
        name = rule[1:-1] if rule.startswith('<') and rule.endswith('>') else rule
        raw[name] = [[to_raw(t) for t in alt] for alt in alts]
    raw = apply_extras_and_bias(raw)
    out = {}
    for name, alts in raw.items():
        key = '<%s>' % name
        out[key] = [[from_raw(t) for t in alt] for alt in alts]
    # Also force <START> to the configured prologue.
    if '<START>' in out:
        out['<START>'] = [[from_raw(t) for t in alt] for alt in START_PROLOGUE]
    with open(path, 'w') as f:
        json.dump(out, f, indent=4)
        f.write('\n')


def remove_grammar_comments(grammar):
    """Delete all the C code comments."""

    # Cf. https://stackoverflow.com/questions/241327/remove-c-and-c-comments-using-python/241506#241506

    def replacer(match):
        s = match.group(0)
        if s.startswith('/'):
            return ' ' # note: a space and not an empty string
        else:
            return s

    regex = re.compile(
        r'//.*?$|/\*.*?\*/|\'(?:\\.|[^\\\'])*\'|"(?:\\.|[^\\"])*"',
        re.DOTALL | re.MULTILINE
    )

    return regex.sub(replacer, grammar)


def remove_grammar_actions(grammar):
    """Delete all the C code handling tokens."""

    remaining = ''

    scope = 0
    string = False

    for ch in grammar:

        if ch == '{' and not(string):
            scope += 1

        elif ch == '}' and not(string):
            assert(scope > 0)
            scope -= 1

        elif scope == 0:
            remaining += ch
            if ch == '"' or ch == "'":
                string = not(string)

    return remaining


def normalize_rule_terminators(grammar):
    """Insert the optional rule-terminating ';' where Bison lets it be omitted.

    parse_rules() splits on ';', so a rule that ends without one swallows the
    rule that follows it (upstream `expr_reader` does exactly this).
    """

    head = re.compile(r'(?m)^([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?:\n[ \t]*)?:')

    out = []
    last = 0

    for m in head.finditer(grammar):
        start = m.start()
        before = grammar[last:start]
        stripped = before.rstrip()
        if stripped and not stripped.endswith(';'):
            before = stripped + '\n;\n'
        out.append(before)
        out.append(m.group(0))
        last = m.end()

    out.append(grammar[last:])

    return ''.join(out)


def is_upper(text):
    """State if a string is upper case."""

    return text.upper() == text


def parse_rule_definition(grammar):
    """Process the definition of one rule."""

    result = []

    # Do not split on a '|' / "|" that is itself a terminal.
    regex = re.compile('(?<![\'"])\\|(?![\'"])')

    definitions = regex.split(grammar)

    definitions = [ d.strip() for d in definitions ]


    for d in definitions:
        tokens = d.split()

        converted = []

        skip_next = False

        for t in tokens:
            # `%prec TOKEN` only sets precedence; TOKEN is not part of the rule.
            if skip_next:
                skip_next = False
                continue
            if t == "%prec":
                skip_next = True
                continue
            # bison's error-recovery token has no textual form.
            if t == "error":
                converted = None
                break
            if not t.startswith("'['") and not t.startswith('"["'):
                t = t.split('[')[0]
            else:
                t = "'['"

            if t == '':
                continue
            if t.startswith("'"):
                t = '"' + t[1:-1] + '"'
                converted.append('%s' % t)
            elif t == "SEMICOLON":
                converted.append('";"')
            elif t == "COMMA":
                converted.append('","')
            elif not(t.startswith('"')) and is_upper(t):

                if not(t in __lexer_tokens.keys()):
                    print('Missing def:', t)
                    sys.exit()

                assert(t in __lexer_tokens.keys())

                converted.append('"<%s>"' % t.lower())

            else:
                converted.append('"<%s>"' % t)

        if converted is None:
            continue

        result.append(converted)
    return result


def parse_rules(grammar):
    """Process all the rules contained in the grammar."""

    tree = {}

    # A rule body may contain a quoted ';' terminal — match quoted chunks
    # atomically so only a bare ';' ends the rule.
    regex = re.compile('[\n\t ]*([^\n\t :]+)[\n\t ]*:((?:\'[^\']*\'|[^;])*);')

    rules = regex.findall(grammar)

    first = True

    for r in rules:
        if first:
            print('    "<START>": [ ["<%s>"] ],' % r[0])
            first = False

        definitions = parse_rule_definition(r[1])

        tree[r[0]] = definitions

    return tree


def simplify_tree(tree):
    """Remove nodes which only are links between two levels of nodes."""

    """
    a = [ [b] ]
    b = [ [c], [d] ]

    -> replace a by b
    """

    # Examples: cexpression, modifier_arg

    replaced = {}

    for k, v in tree.items():

        if len(v) == 1 and len(v[0]) == 1:

            replaced['"<%s>"' % k] = v[0][0]

    new_tree = {}

    for k, v in tree.items():

        name = '"<%s>"' % k

        if not(name in replaced.keys()):

            new_v = []

            for vv in v:

                new_vv = vv

                for rk, rv in replaced.items():
                    new_vv = list(map(lambda x: x.replace(rk, rv), new_vv))

                new_v.append(new_vv)

            new_tree[k] = new_v

    return new_tree


def find_direct_parent_nodes(tree, name):
    """Find all the rules containing a rule."""

    rules = []

    name = '"<%s>"' % name

    for k, v in tree.items():

        for vv in v:

            if len(vv) == 1 and vv[0] == name and not(k in rules):

                rules.append(k)

    return rules


def remove_indirect_left_recursion(tree):
    """Remove all nodes which implies indirect left recursion."""

    """
    a = b
    b = a + c

    -> a = a + c
    """

    # Examples: logical_expr, relational_expr, string_op, arithm_expr, intersection

    replaced = {}

    for k, v in tree.items():

        parents = find_direct_parent_nodes(tree, k)

        if len(parents) != 1:
            continue

        parent = parents[0]

        for vv in v:

            if vv[0] == '"<%s>"' % parent:
                replaced[k] = v
                break

    # Inlining only rewrites single-symbol alternatives ("<k>" alone). A rule
    # that is also referenced inside a longer alternative cannot be dropped —
    # doing so would leave a dangling "<k>" the generator emits verbatim.
    for k in list(replaced.keys()):
        token = '"<%s>"' % k
        for kk, vv in tree.items():
            if any(len(alt) != 1 and token in alt for alt in vv):
                del replaced[k]
                break

    new_tree = {}

    for k, v in tree.items():

        if not(k in replaced.keys()):

            new_v = []

            for vv in v:

                if len(vv) != 1:
                    new_v.append(vv)

                else:

                    modified = False

                    for rk, rv in replaced.items():
                        if '"<%s>"' % rk == vv[0]:
                            new_v += rv
                            modified = True
                            break

                    if not(modified):
                        new_v.append(vv)

            new_tree[k] = new_v

    return new_tree


def output_rules(tree):
    """Output a translated rule."""

    for k, v in tree.items():

        print('    "<%s>": [' % k, end='')

        first = True

        for d in v:

            if not(first):
                print(',', end='')

            if len(d) == 0:
                print(' []', end='')

            else:

                print(' [', end='')

                sub_first = True

                for sub_d in d:

                    if not(sub_first):
                        print(', ', end='')

                    print('%s' % sub_d, end='')

                    sub_first = False

                print(']', end='')

            first = False

        print(' ],')


if __name__ == '__main__':
    """Script entrypoint."""

    # Cf. https://github.com/AFLplusplus/Grammar-Mutator/blob/stable/doc/customizing-grammars.md

    if len(sys.argv) >= 3 and sys.argv[1] == '--apply':
        apply_to_json(sys.argv[2])
        sys.exit(0)

    with open(sys.argv[1], 'r') as fd:
        grammar = fd.read()

    grammar = grammar.split('%%')[1]

    grammar = remove_grammar_comments(grammar)

    grammar = remove_grammar_actions(grammar)

    grammar = normalize_rule_terminators(grammar)

    print('{')

    tree = parse_rules(grammar)

    tree = simplify_tree(tree)

    tree = remove_indirect_left_recursion(tree)

    tree = apply_extras_and_bias(tree)

    output_rules(tree)

    count = len(__lexer_tokens.keys())

    for name, cb in __lexer_tokens.items():
        cb(name, count == 1)
        count -= 1

    print('}')
