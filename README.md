# zmr-tool
zmr (zoomer) is a zoom-and-replace tool for navigating and transforming nested code regions. The command zooms into a specific code block defined by patterns and performs regex or literal substitutions, shell commands, and template substitutions. In addition to stdin and stdout, it supports in-place editing of both regular and archived text files.

## 1. Main Capabilities

- **Order-preserving editing:** Changes are confined to matched regions, ensuring the overall file structure remains intact.
- **Multi-level nesting support:** Enables deep navigation through layered code constructs like functions, if-statements, loops, and blocks.
- **Balanced delimiter handling:** Supports standard delimiters `{}`, `()`, `[]`, and custom start/end markers with depth tracking.
- **Backtracking mechanism:** Recovers from false matches enhancing robustness.
- **Archive processing:** Reads and modifies files within `.tar`, `.tar.gz`, and `.zip` archives, with atomic write operations to prevent corruption.
- **Multi-encoding support:** Handles UTF-8 files with Latin-1 fallback for legacy or mixed-encoding files.
- **Preview mode:** Visualizes nested regions with ANSI color codes for clarity before applying changes.
- **In-place editing:** Supports direct file modifications with optional backup creation.
- **Transformation flexibility:** Supports regex (`-r`), literal (`-l`), and shell command piping (`-x`).

---

## 2. Examples

### 2.1 Zooming

Preview mode (`-p0`) shows the matched region in red color (which not supported by the `.md` format):
```bash
$ zmr -z 'void bar(int i) {_}' -z 'while (i--) {_}' -r 's/world/WORLD/' hello.c -p0
{
    printf("WORLD\n");
  }
```

Preview mode (`-p1`) shows the matched region in red and the surrounding region in green so we see a little more context:
```
$ zmr -z 'void bar(int i) {_}' -z 'while (i--) {_}' -r 's/world/WORLD/' hello.c -p1
{
  while (i--) {
    printf("WORLD\n");
  }
}
```

If we drop the underscore from the patterns, we get a slightly larger match which is best illustrated in the preview mode (`-p0`):
```
$ zmr -z 'void bar(int i) {}' -z 'while (i--) {}' -r 's/world/WORLD/' hello.c -p0
while (i--) {
    printf("WORLD\n");
  }
```

Again, preview mode (`-p1`) shows not only the matching region (in red) but also the surrounding region (in green):
```
$ zmr -z 'void bar(int i) {}' -z 'while (i--) {}' -r 's/world/WORLD/' hello.c -p1
void bar(int i) {
  while (i--) {
    printf("WORLD\n");
  }
}
```

Mixing different delimiter types together in zoom patterns is not allowed:
```
$ zmr -z 'void foo() {}' -r 's/hello/HELLO/' hello.c -p0
ERROR: Definition contains multiple marker types
```

If we want to match a literal `()` from the file, we can write it with an extra space in between, i.e. `( )`, because the zoom pattern matching engine ignores white space unless it introduces a new word boundaries just like many compilers do:
```
$ zmr -z 'void foo( ) {}' -r 's/hello/HELLO/' hello.c -p0
void foo() {
  printf("HELLO!\n");
}
```

Leaving out the underscore from the zoom patterns means that whole pattern is matched from start to finish:
```
$ zmr -z 'if ($x) {} elseif ($y) {} else {}' < elseif.php -p0
if ($x) {
    cmd1();
  } elseif ($y) {
    cmd2();
  } else {
    cmd3();
  }
```

By contrast, adding a single underscore to the zoom pattern we can zoom into that specific branch:
```
$ zmr -z 'if ($x) {} elseif ($y) {_} else {}' < elseif.php -p0
{
    cmd2();
  }
```

Instead of the regular zoom patters, a similar effect can be achieved with the `-s (--start)` and `-e (--end)` options:
```
$ zmr -s '<a>' -e '</a>' -s '<a>' -e '</a>' -x 'tr a-z A-Z' < test.xml -p0
<A>  # 2 OPEN
    <B></B>  # 3 OPEN AND CLOSE
  </A>
```

There are far better tools for processing XML files, and the purpose of these examples is to show that the concept of nested regions maps cleanly to tree-like structures:
```
$ zmr -s '<a>' -e '</a>' -s '<a>' -e '</a>' -x 'tr a-z A-Z' < test.xml -p1
<a>  # 1 open
  <A>  # 2 OPEN
    <B></B>  # 3 OPEN AND CLOSE
  </A>  # 2 close
</a>
```

### 2.2 Transforming

We can pipe the selected region through an external command with the `-x (--exec)` option:
```
$ zmr -z 'int main(int argc, char *argv[]) {_}' -z 'if (strcmp(argv[1], "help") == 0) {_}' -x 'tr a-z A-Z' < hello.c -p1
{
  foo();
  bar(5);
  baz();

  if (argc > 1) {
    if (strcmp(argv[1], "help") == 0) {
      PRINTF("HELP REQUESTED!\N");
    }
  } /* if */
  return 0;
}
```

Templates can be read from a file or from `stdin` just like the input files:
```
$ zmr -z 'void foo() {_}' -t templates/foo_body.c < hello.c -p0
  printf("goodbye!\n");
$ zmr -z 'void foo() {_}' -t - < templates/foo_body.c hello.c -p0
  printf("goodbye!\n");
```

Templates can also be followed by other transformations:
```
$ zmr -z 'void foo() {_}' -t templates/foo_body.c -x 'tr a-z A-Z' < hello.c -p0
  PRINTF("GOODBYE!\N");
```

The special value `:` for an empty template was inspired by the `:` no-op shell command. These two are equivalent except that the `-t` parameter does not launch an external process:
```
$ zmr -z 'void foo( ) {}' -x ':' hello.c -p0    # removes foo() with a process the returns nothing
$ zmr -z 'void foo( ) {}' -t ':' hello.c -p0    # removes foo() by substituting an empty template
```

### 2.3 Working with Archive Files

Editing a file inside a zip archive (change the `-p0` flag to `-i` flag to actually write the changes to the archive):
```
$ zmr -a test.zip -z 'function hello() {_}' -r 's/TODO/DONE/' src/main.js -p0
{
    // DONE: improve this
    console.log("hello world");
}
```

In addition to `.zip` files, also `.tar` and `.tar.gz` files are supported. It is also possible to peek inside archives without even specifying any zoom patterns or translations:
```
$ zmr -a test.tar.gz src/main.js
function hello() {
    // TODO: improve this
    console.log("hello world");
}

function goodbye() {
    console.log("goodbye");
}
```

---

## 3. Command-line Options

### 3.1 Zoom (`-z / --zoom`)

Defines nested regions via pattern matching.

- Supports multiple zoom levels, applied from outermost to innermost
- Supports flexible token markers: `{}`, `{_}`, `()`, `(_)`, `[]`, `[_]`, custom patterns
- Example 1: `-z 'function bar() {_}'` zooms into the function block body
- Example 2: `-z 'function bar() {}'` zooms into the whole function definition

### 3.2 Transformation

#### Regex (`-r / --regex`)
- Substitution with sed-style flexible delimiters
- Supports flags: `g` (global), `i` (case-insensitive), `gi`/`ig` (both)
- Full Python `re` module syntax with backreferences

#### Literal (`-l / --literal`)
- Non-regex string replacement
- Supports flags: `g` (global), `i` (case-insensitive)
- Plain string matching, no regex features

#### Shell Command (`-x / --exec`)
- Pipes the innermost region through a shell command
- Transforms the text dynamically via subprocess

### 3.3 Boundary Markers (`-s / --start`, `-e / --end`)

Define inclusive start/end boundaries for regions.

- Supports nested and balanced matching
- Useful for regions marked by specific tokens, e.g., `// START` and `// END`
- Ensures precise targeting of regions

### 3.4 Template Replacement (`-t / --template`)

Replaces the innermost region with template file contents.

- Special values:
  - `:` replaces region with an empty string
  - `-` reads template from stdin
- Can be followed with other transformations

### 3.5 Preview Mode (`-p LEVELS`)

Visualizes nested regions with color coding.

- Level 0: innermost only
- Level 1: innermost + next level
- Level 2: innermost + next two levels
- Level 3+: all levels with default colors

### 3.6 Archive Handling (`-a / --archive`)

Enables reading from and writing to files inside archives.

- Supports formats: `.tar`, `.tar.gz`, `.zip`
- Reads files with encoding fallback (UTF-8, then Latin-1)
- Modifications committed atomically, preserving metadata

### 3.7 In-place Editing (`-i[SUFFIX]`)

Edits files directly.

- Creates backups if suffix provided (e.g., `-i.bak`)
- Cannot be combined with preview mode
- Modifications written back atomically

### 3.8 Debugging (`-d / --debug`)

Outputs detailed matching and escaped text info to stderr.

---

## 4. Invocation Syntax

```
zmr [-z DEF ...] [-s PAT] [-e PAT] [-r EXPR ...] [-l EXPR ...] 
    [-x CMD ...] [-t TEMPLATE] [-p LEVELS] [-a ARCHIVE] 
    [-i[SUFFIX]] [FILE ...]
```

### Input/Output

- Reads from specified files or stdin
- When `-a` (archive mode) used, FILE arguments refer to archive member paths
- Default output to stdout; `-i` for in-place file editing; `-p` for preview mode

### Exit Codes

- **0:** Success with no errors
- **1:** No match found for specified pattern
- **2:** Error (invalid arguments, I/O issues, regex errors, unmatched regions, shell command failures)

---

## 5. Transformation Expressions

Follow sed-style syntax: `s<delim>pattern<delim>replacement<delim>[flags]`

### Delimiters

Any character except backslash; supports escaping within patterns.

### Flags

- `g`: global replacement
- `i`: case-insensitive
- `gi` or `ig`: both flags combined

### Pattern Types

- **Regex (`-r`):** Full Python `re` module syntax, supports backreferences
- **Literal (`-l`):** Plain string matching, no regex features
- **Shell piping (`-x`):** Executes commands on region content

---

## 6. Modes of Operation

- **No-op:** Reads files/stdin without modifications
- **Preview:** Shows colored nested regions without editing a file
- **Transform:** Applies specified transformations to regions
- **In-place:** Edits a file directly with an optional backup
- **Archive modes:** Read-only or in-place modifications of archive contents

---

## 7. Comment and String Handling (Internal Implementation)

- Comments (`//`, `#`, `/* */`) and string literals (`"..."`, `'...'`) replaced with equal-length spaces before matching `{}`, `()`, and `[]` delimiters
- This prevents false matches within comments or strings
- String literals processed before comments to avoid false positives in code or URLs, e.g. "http://localhost" contains //, which could be mistaken for the start of a comment if comments were processed first
- Original text restored after matching, ensuring positional integrity

---

## 8. File Processing

- Files specified as positional arguments or via wildcards
- Reads from stdin if no files specified
- Output modes:
  - stdout (default or preview)
  - Overwrite files (`-i`) with optional backups
  - Process files inside archives with atomic updates
- Backup strategy: `-i.bak` creates backup before overwrite
- Archive support:
  - Reads/writes files within archives
  - Preserves file metadata
  - Supports multiple files in single archive modification

---

## 9. Test Coverage (69 Tests)

| Category | Tests | Coverage |
|----------|-------|----------|
| 1. Basic Zoom | 11 | Zoom, nesting, region selection |
| 2. Backtracking | 8 | Algorithm robustness, edge cases |
| 3. Transform | 13 | Regex, literal, shell, encoding |
| 4. Template | 7 | Replacement, BOM stripping |
| 5. File I/O | 8 | File reading, archives, encoding |
| 6. In-Place | 13 | Editing, backups, encoding |
| 7. Combined | 11 | Real-world multi-step workflows |

### Encoding Test Cases

- **3.3b:** Latin-1 input + ASCII transform = Latin-1 output (preserved)
- **3.3c:** Latin-1 input + UTF-8 transform = UTF-8 output (warned)
- **4.5:** BOM stripping from template files
- **5.1b:** Latin-1 file reading preserves encoding
- **5.1c:** Latin-1 file + UTF-8 transform = UTF-8 output (warned)
- **6.1c:** In-place Latin-1 editing (ASCII) preserves encoding
- **6.1d:** In-place Latin-1 editing (UTF-8) converts with warning

---

## 10. Error Handling

- **Exit code 2:** Critical errors like invalid syntax, regex errors, file I/O failures, unmatched regions, or shell command failures
- **Exit code 1:** No match found for specified pattern (useful for scripting)
- Provides detailed error messages for debugging

---

## 11. Limitations & Constraints

- Max preview colors: 3 levels
- Only one marker per zoom definition; one target region per nesting level
- Delimiters must be balanced; input source code must be well-formed
- Regex syntax based on Python's `re` module, supporting advanced features
- String/comment replacement preserves position but may limit some complex patterns
- Transformation occurs after zoom navigation; cannot filter regions post-transform
- Specifying identical `--start` and `--end` patterns is treated as an error
- Binary files should not be processed; they are most likely misinterpreted as Latin-1 text

---

## 12. Technical Implementation Details

### 12.1 Balanced Delimiter Algorithm

- Uses depth counting during iterative scan of escaped text
- Delimiters inside strings/comments invisible due to prior replacement
- Supports nested matching with depth tracking

### 12.2 Substitution Methods

- **Regex:** Uses `re.sub()` with flags
- **Literal:** Escapes pattern, then uses `re.sub()` with replacement function
- **Shell execution:** Uses `subprocess.run()` with `shell=True`, passing region via stdin

### 12.3 Performance

- Linear traversal (O(n)) for escaping and delimiter detection
- Uses compiled regex for efficiency
- May degrade with deep nesting or complex patterns

### 12.4 Equal-Length Placeholder System

- Replaces comments/string literals with spaces of equal length
- Ensures position mapping remains accurate
- Facilitates precise boundary detection despite code modifications

### 12.5 Mixed-Space Pattern Matching

- Tokens matched against original text
- Delimiters matched against escaped text
- Maintains positional consistency across transformations

### 12.6 Encoding Strategy Implementation

- **Detection:** UTF-8 try/except, fall back to Latin-1
- **Preservation:** Track detected encoding through transformations
- **Output:** Tier I (UTF-8 direct), Tier II (try Latin-1), Tier III (warn + UTF-8)
- **Archives:** Per-member encoding detection and conversion

---

## 13. Comparison with Related Tools

| Tool | Zoom/Nesting | Regex | Literal | Multi-Encoding |
|------|--------------|-------|---------|-----------------|
| sed | — | x | x | — |
| awk | — | x | — | — |
| perl | — | x | x | — |
| **zmr** | **x** | **x** | **x** | **x** |

zmr distinguishes itself by enabling multi-level nested navigation akin to compiler tokenization, combined with precise transformations and multi-encoding support, making it uniquely suitable for complex code refactoring and structured text modifications in mixed-environment settings.

---

## 14. Key Features - v6.0.2

### 14.1 Multi-Encoding Support

zmr implements a 3-tier encoding strategy for handling mixed-encoding environments:

#### Tier I: UTF-8 (standard case)
- If input file is valid UTF-8, process and output as UTF-8
- No encoding warnings or changes
- Covers most use cases

#### Tier II: Latin-1 Preservation (legacy support)
- If UTF-8 decode fails, fall back to Latin-1 (always succeeds)
- Process internally as UTF-8 strings (Python 3 strings are Unicode)
- Attempt to encode output back to original Latin-1 encoding
- If successful, output preserves original encoding (no change)
- Covers use cases involving legacy/Windows files

#### Tier III: UTF-8 with Warning (edge cases)
- If Tier II encode fails (transformation introduced non-Latin-1 characters)
- Output as UTF-8 with warning to stderr
- Warning message: `WARNING: {filename}: output contains characters outside LATIN-1, converting to UTF-8`
- Covers rare edge cases (Latin-1 input + UTF-8 template/replacement)

### 14.2 BOM Stripping

- UTF-8 BOM (Byte Order Mark, U+FEFF) is automatically stripped from template files
- Prevents BOM duplication when templates are used
- Both file-based and stdin templates are cleaned

### 14.3 Archive Member Encoding

- Each archive member follows the same 3-tier encoding strategy
- Independent detection and conversion per member
- If a file is converted to UTF-8 as a result of a transformation, member is converted with warning

---

## 15. Version History

### v6.0.2 (Latest)

- 3-tier encoding strategy for multi-encoding support (UTF-8, Latin-1 preservation, UTF-8+warn)
- BOM stripping from template files
- Archive members follow encoding preservation rules
- 69 comprehensive tests with encoding validation
- Removed non-ASCII characters from code for clean implementation

### v6.0.1

- Fixed stdin encoding handling with `safe_decode`/`safe_decode_simple`
- File reading uses binary mode with encoding detection

### v6.0.0

- Initial stable release with core functionality
- Zoom, transform, template, preview, in-place, archive support
- Safe backtracking algorithm
- Comment/string handling

---

## Main Objectives & Unique Selling Points

- Enable precise, nested, and order-preserving code transformations
- Support complex boundary definitions with balanced delimiters and custom markers
- Facilitate batch processing and archive modifications with atomic safety
- Provide visual preview modes for safe editing
- Leverage advanced pattern matching and flexible syntax for diverse use cases
- Handle mixed-encoding environments gracefully with 3-tier strategy

**Overall, zmr (Zoomer) is a powerful, flexible, and robust tool tailored for developers and code maintainers requiring granular control over nested code regions, supporting complex workflows with multi-encoding compatibility that traditional text processing tools cannot easily handle.**
