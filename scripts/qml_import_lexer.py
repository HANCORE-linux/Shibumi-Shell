"""Conservative QML/ECMAScript lexical scanning, not a syntax validator.

Strings, comments and regexp bodies are opaque. Template interpolations are
code. Ambiguous regexp/division contexts refuse rather than hiding tokens.
"""
from dataclasses import dataclass


class ImportLexError(ValueError):
    def __init__(self, offset, message):
        self.offset = offset
        super().__init__(message)


@dataclass(frozen=True, slots=True)
class Token:
    kind: str
    text: str
    start: int
    end: int

    @property
    def span(self):
        return self.start, self.end


class Lexer:
    def __init__(self, text):
        self.text = text
        self.position = 0

    def quoted(self, quote):
        start = self.position
        self.position += 1
        while self.position < len(self.text):
            char = self.text[self.position]
            self.position += 1
            if char == "\\":
                self.position += 1
            elif char == quote:
                return Token("string", self.text[start:self.position], start, self.position)
        raise ImportLexError(start, "unterminated string")

    def regexp_end(self):
        index = self.position + 1
        in_class = False
        while index < len(self.text):
            char = self.text[index]
            if char in "\r\n\u2028\u2029":
                return None
            if char == "\\":
                if index + 1 < len(self.text) and self.text[index + 1] in "\r\n\u2028\u2029":
                    return None
                index += 2
                continue
            if char == "[":
                in_class = True
            elif char == "]":
                in_class = False
            elif char == "/" and not in_class:
                index += 1
                flags_start = index
                while index < len(self.text) and (self.text[index].isalnum()
                        or self.text[index] in "_$\\"):
                    index += 1
                flags = self.text[flags_start:index]
                if any(flag not in "gimuy" for flag in flags) or len(set(flags)) != len(flags):
                    return None
                return index
            index += 1
        return None

    def template(self, depth):
        start = self.position
        self.position += 1
        yield Token("template", "`", start, self.position)
        while self.position < len(self.text):
            char = self.text[self.position]
            if char == "\\":
                self.position += 2
            elif char == "`":
                self.position += 1
                yield Token("template", "`", self.position - 1, self.position)
                return
            elif self.text.startswith("${", self.position):
                self.position += 2
                yield from self.scan(interpolation=True, depth=depth + 1)
            else:
                self.position += 1
        raise ImportLexError(start, "unterminated template")

    def scan(self, interpolation=False, depth=0):
        if depth > 64:
            raise ImportLexError(self.position, "template nesting limit")
        expression = True  # None denotes a deliberately unsupported ambiguity.
        previous = ""
        control_pending = False
        parens = []
        braces = 0
        controls = {"if", "while", "for", "with", "switch", "catch"}
        operators = {"return", "throw", "case", "else", "do", "delete", "void",
                     "typeof", "new", "in", "instanceof", "default", "extends",
                     "break", "continue", "debugger"}
        while self.position < len(self.text):
            start = self.position
            char = self.text[start]
            if char.isspace() or char == "\ufeff":
                self.position += 1
                continue
            if self.text.startswith("//", start):
                while self.position < len(self.text) and self.text[self.position] not in "\r\n\u2028\u2029":
                    self.position += 1
                continue
            if self.text.startswith("/*", start):
                end = self.text.find("*/", start + 2)
                if end < 0:
                    raise ImportLexError(start, "unterminated comment")
                self.position = end + 2
                continue
            if char in "\"'":
                token = self.quoted(char)
                expression = None if previous in {"import", "from"} else False
            elif char == "`":
                yield from self.template(depth)
                previous, expression, control_pending = "template", False, False
                continue
            elif char == "/" and expression is not False:
                end = self.regexp_end()
                if expression is None and end is not None:
                    raise ImportLexError(start, "ambiguous regexp/division")
                if end is None and expression is True:
                    raise ImportLexError(start, "unsupported or unterminated regexp")
                if end is not None:
                    self.position = end
                    token = Token("regexp", self.text[start:end], start, end)
                    expression = False
                else:
                    self.position += 1
                    token = Token("other", "/", start, self.position)
                    expression = True
            elif char in "+-" and self.text.startswith(char * 2, start):
                self.position += 2
                token = Token("other", char * 2, start, self.position)
                # Prefix expects an operand; postfix has already completed it.
            elif char.isalpha() or char in "_$":
                self.position += 1
                while self.position < len(self.text) and (self.text[self.position].isalnum()
                        or self.text[self.position] in "_$\u200c\u200d"
                        or ("a" + self.text[self.position]).isidentifier()):
                    self.position += 1
                value = self.text[start:self.position]
                token = Token("word", value, start, self.position)
                expression = previous != "." and value in operators
                if previous != "." and value in {"await", "yield", "of"}:
                    expression = None
            elif char.isdigit():
                self.position += 1
                while self.position < len(self.text) and (self.text[self.position].isalnum()
                        or self.text[self.position] in "_."):
                    self.position += 1
                token = Token("number", self.text[start:self.position], start, self.position)
                expression = False
            else:
                self.position += 1
                token = Token("other", char, start, self.position)
                if char == "(":
                    if len(parens) >= 256:
                        raise ImportLexError(start, "parenthesis nesting limit")
                    parens.append(control_pending)
                    expression = True
                elif char == ")":
                    expression = parens.pop() if parens else None
                elif char == "{":
                    braces += 1
                    expression = True
                elif char == "}":
                    if interpolation and braces == 0:
                        return
                    braces -= 1
                    expression = None
                elif char in "].":
                    expression = False
                else:
                    expression = None if ord(char) > 127 else True
            control_pending = token.kind == "word" and previous != "." and (
                token.text in controls or (token.text == "await" and previous == "for" and control_pending))
            previous = token.text
            yield token
        if interpolation:
            raise ImportLexError(self.position, "unterminated interpolation")


def tokens(text):
    yield from Lexer(text).scan()
