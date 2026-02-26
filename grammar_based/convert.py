
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


def define_UNSIGNED_INTEGER(name, last):
    """Create definition for the UNSIGNED_INTEGER token."""

    print('    "<%s>": [ ["<fnumber>"], ["<number>", "<fnumber>"], ["<number>", "<fnumber>", "<fnumber>"] ],' % name.lower())
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


__lexer_tokens = {
    'PLAIN_TEXT': define_PLAIN_TEXT,
    'ESCAPED_TEXT': define_PLAIN_TEXT,
    'RULE_IDENTIFIER': define_IDENTIFIER,
    'INFO_KEY': define_PLAIN_TEXT,
    'SIGNED_INTEGER': define_SIGNED_INTEGER,
    'UNSIGNED_INTEGER': define_UNSIGNED_INTEGER,

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

    'NAME': define_PLAIN_TEXT,
    'HEX_BYTES': define_HEX_BYTES,
    'FULL_MASK': define_FULL_MASK,
    'SEMI_MASK': define_SEMI_MASK,
    'REGEX_BYTES': define_PLAIN_TEXT,
    'REGEX_CLASSES': define_PLAIN_TEXT,
    'REGEX_RANGE': define_PLAIN_TEXT,
    'KB': define_KB,
    'MB': define_MB,
    'GB': define_GB,
}


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
            if ch == '"':
                string = not(string)

    return remaining


def is_upper(text):
    """State if a string is upper case."""

    return text.upper() == text


def parse_rule_definition(grammar):
    """Process the definition of one rule."""

    result = []

    regex = re.compile('(?<!")\|')

    definitions = regex.split(grammar)

    definitions = [ d.strip() for d in definitions ]

    for d in definitions:

        tokens = d.split()

        converted = []

        for t in tokens:

            if not(t.startswith('"')) and is_upper(t):

                if not(t in __lexer_tokens.keys()):
                    print('Missing def:', t)
                    sys.exit()

                assert(t in __lexer_tokens.keys())

                converted.append('"<%s>"' % t.lower())

            else:

                if t.startswith('"'):
                    converted.append('%s' % t)
                else:
                    converted.append('"<%s>"' % t)

        result.append(converted)

    return result


def parse_rules(grammar):
    """Process all the rules contained in the grammar."""

    tree = {}

    regex = re.compile('[\n\t ]*([^\n\t :]+)[\n\t ]*:([^;]+);')

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

    with open(sys.argv[1], 'r') as fd:
        grammar = fd.read()

    grammar = grammar.split('%%')[1]

    grammar = remove_grammar_comments(grammar)

    grammar = remove_grammar_actions(grammar)

    print('{')

    tree = parse_rules(grammar)

    tree = simplify_tree(tree)

    tree = remove_indirect_left_recursion(tree)

    output_rules(tree)

    count = len(__lexer_tokens.keys())

    for name, cb in __lexer_tokens.items():
        cb(name, count == 1)
        count -= 1

    print('}')
