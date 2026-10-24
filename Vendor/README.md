# Vendored tree-sitter sources

Skald highlights code with the tree-sitter C runtime and one generated parser per
language, compiled straight into the app. Nothing is fetched at build time and the app
itself never touches the network.

The upstream repositories are cloned into `Vendor/upstream/` (git-ignored), and
`Scripts/vendor-tree-sitter.sh` copies exactly the files the build needs into
`Skald/Vendor/` (committed) and the highlight queries into `Skald/Resources/Queries/`.

## 1. Clone upstream (run once, outside the sandbox)

```bash
mkdir -p Vendor/upstream && cd Vendor/upstream
git clone --depth 1 https://github.com/tree-sitter/tree-sitter.git
git clone --depth 1 --branch with-generated-files https://github.com/alex-pinkus/tree-sitter-swift.git
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-python.git
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-json.git
git clone --depth 1 https://github.com/tree-sitter-grammars/tree-sitter-markdown.git
git clone --depth 1 https://github.com/tree-sitter-grammars/tree-sitter-yaml.git
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-bash.git
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-html.git
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-css.git
git clone --depth 1 https://github.com/tree-sitter-grammars/tree-sitter-xml.git
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-javascript.git
git clone --depth 1 https://github.com/tree-sitter/tree-sitter-typescript.git
```

Languages: Swift, Python, JSON, Markdown (block + inline), YAML, Shell, HTML, CSS,
XML (also .svg, .plist), JavaScript (also .jsx), TypeScript, TSX.

## Adding a language

1. Clone its repo into `Vendor/upstream`.
2. Add one line to `GRAMMARS` in `Scripts/vendor-tree-sitter.sh` (name, source dir, C
   symbol, optional shared-header dir, optional query files, optional injections file).
3. Add one `LanguageDefinition` to `LanguageRegistry` and one entry to
   `TreeSitterSupport.grammarFunctions`.
4. Run the script, then `Scripts/test-cli.sh SkaldTests.TreeSitterParserTests`.

`tree-sitter-swift` keeps its generated `parser.c` on the `with-generated-files`
branch; the default branch has none.

## 2. Copy what the build needs

```bash
Scripts/vendor-tree-sitter.sh
```

The script also prints each grammar's `LANGUAGE_VERSION` next to the runtime's
supported range. A grammar outside that range is rejected by `ts_parser_set_language`
at runtime with no other symptom, so fix any mismatch before building.

## Precedence and local patches

When several patterns capture the same node, the later pattern in the query file wins,
matching the current tree-sitter CLI and the grammars' own highlight test corpora
(`test/highlight/`). The JSON query predates that rule, so the script appends one
pattern to `json.highlights.scm` re-asserting `@string.special.key` for object keys.
`@spell`/`@nospell` captures are ignored; `@none` clears highlighting for its range.

Some grammars build their highlight query from several files (JavaScript: base + JSX +
params; TypeScript and TSX: their own file plus JavaScript's). The script concatenates
them in the `GRAMMARS` order. For TSX the JSX file goes last, unlike upstream's
`tree-sitter.json`, because the general JavaScript patterns would otherwise override
every JSX tag.

Repos with a shared `common/scanner.h` (XML, TypeScript) keep their `<grammar>/src`
layout under `Skald/Vendor/Grammars/<name>/` so the `../../common` include resolves,
and the grammar's `tree_sitter/` headers are copied beside the shared header.

Xcode compiles every `.c` file under `Skald/Vendor` as part of the app target. The Swift
grammar's `parser.c` is large, so the first build takes a while; later builds are
incremental.

## Licenses

All projects are MIT licensed (the ICU unicode headers inside the runtime carry their
own license). The script copies each `LICENSE` into `Skald/Vendor/LICENSES/`.

## Injections

Markdown ships two grammars. Both are vendored: the block grammar owns the document
and its `injections.scm` hands paragraph text to `markdown_inline` and fenced code to
the language named in the fence (`swift`, `python`, `json`, `yaml`). The adapter reads
that query generically, so any grammar with an `injections.scm` and `#set!
injection.language` directives gets the same treatment. Languages we do not compile
(html, toml) are skipped.
