# zmr Test Suite

## Structure

    run_tests.sh            Main test driver
    fixtures/
        hello.c             C source with functions, nested ifs, strings in args
        elseif.php          PHP with elseif chain
        sample.php          PHP with boundary markers (section-start/end)
        backtrack.php       PHP with two foo() functions and comment-embedded tokens
        test.xml            XML with nested <a><b> structure
        test.tar.gz         Tar archive (src/main.js, config.ini, readme.txt)
        test.zip            Zip archive (same contents as test.tar.gz)
        latin1-content.txt  Latin-1 encoded file with non-ASCII character (O-Umlaut)
        bom-template.txt    UTF-8 template file with leading BOM (for BOM-strip test)
        euro-template.txt   UTF-8 template file containing the Euro sign (U+20AC)
        templates/
            foo_body.c      Template: replacement body for void foo()
            hello_body.js   Template: replacement body for function hello()

## Usage

    ./run_tests.sh path/to/zmr          # run all categories
    ./run_tests.sh path/to/zmr zoom      # run only zoom tests
    ./run_tests.sh path/to/zmr backtrack
    ./run_tests.sh path/to/zmr transform
    ./run_tests.sh path/to/zmr template
    ./run_tests.sh path/to/zmr fileio
    ./run_tests.sh path/to/zmr inplace
    ./run_tests.sh path/to/zmr combined

Default zmr path: `../zmr` (i.e. zmr is one directory up from the tests folder)

## Test Categories

1. **zoom**       Basic zoom tests (stdin/stdout, no transforms) - 11 tests
2. **backtrack**  Backtracking: algorithm robustness against false delimiter matches - 8 tests
3. **transform**  Regex, literal, exec transforms; encoding preservation - 13 tests
4. **template**   Template replacement, kill, stdin, BOM stripping - 7 tests
5. **fileio**     File input, tar/zip archive reading, encoding detection - 8 tests
6. **inplace**    In-place editing: filesystem files, tar/zip archives, encoding - 11 tests
7. **combined**   Real-world: zoom + transform + in-place + archive - 11 tests

**Total: 69 tests**

## Test Inventory

### 1. Basic Zoom (11)
| Test | Description |
|------|-------------|
| 1.1  | zoom into void foo() body |
| 1.2  | zoom into void bar(int i) body |
| 1.3  | double zoom bar->while body |
| 1.4  | zoom into main() body contains foo() |
| 1.5  | zoom into else branch |
| 1.6  | zoom function bar() from stdin |
| 1.7  | zoom into else branch of elseif |
| 1.8  | start/end: foo to bar |
| 1.9  | zoom+start/end within baz() |
| 1.10 | no-op passthrough (stdin) |
| 1.11 | no-op passthrough (file arg) |

### 2. Backtracking Zoom (8)
| Test | Description |
|------|-------------|
| 2.1  | balanced delimiters in pattern don't confuse matching |
| 2.2  | comment does not confuse brace matching |
| 2.3  | nested zoom skips intervening code |
| 2.4  | find second foo() (must backtrack from first) |
| 2.5  | skip comment token to find real cmd1() |
| 2.6  | find deeply nested call |
| 2.7  | find function in different scope |
| 2.8  | backtrack + transform: correct region modified |

### 3. Transform (13)
| Test | Description |
|------|-------------|
| 3.1  | regex replace hello->HELLO in foo() |
| 3.1b | rest of file unchanged after foo() |
| 3.2  | global regex replace all printf occurrences |
| 3.2b | no lowercase printf remaining |
| 3.3  | literal replace hello!->goodbye! |
| 3.3b | Latin-1 input + ASCII replacement = Latin-1 output (encoding preserved) |
| 3.3c | Latin-1 input + UTF-8 replacement = UTF-8 output (warned) |
| 3.4  | literal case-insensitive replace |
| 3.5  | multiple transforms applied in order |
| 3.6  | exit code 1 when regex has no match |
| 3.7  | exit code 0 with no transforms |
| 3.8  | exec transform (tr a-z A-Z) |
| 3.9  | regex with | delimiter |

### 4. Template (7)
| Test | Description |
|------|-------------|
| 4.1  | template file replaces region |
| 4.1b | rest of file intact after template |
| 4.2  | ':' kills region (hello removed) |
| 4.2b | rest of file intact after kill |
| 4.3  | template + regex rendering |
| 4.4  | template from stdin (-t -) |
| 4.5  | BOM stripped from template file |

### 5. File I/O (8)
| Test | Description |
|------|-------------|
| 5.1  | read file from filesystem |
| 5.1b | Latin-1 file read: encoding preserved in output |
| 5.1c | Latin-1 file + UTF-8 transform: converted to UTF-8 with warning |
| 5.2  | read member from tar archive |
| 5.3  | read member from zip archive |
| 5.4  | read config.ini from tar archive |
| 5.5  | read readme.txt from tar archive |
| 5.6  | exit code 2 for missing archive member |

### 6. In-Place Editing (11)
| Test | Description |
|------|-------------|
| 6.1  | in-place file edit modifies file |
| 6.1b | in-place: rest of file intact |
| 6.1c | Latin-1 in-place + ASCII transform: encoding preserved |
| 6.1d | Latin-1 in-place + UTF-8 transform: converted to UTF-8 with warning |
| 6.2  | backup file created |
| 6.2b | backup has original content |
| 6.2c | modified file has new content |
| 6.3  | in-place tar archive edit |
| 6.3b | TODO replaced in tar |
| 6.4  | in-place zip archive edit |
| 6.5  | unmodified archive member unchanged |

### 7. Combined Real-World (11)
| Test | Description |
|------|-------------|
| 7.1  | zoom+transform+inplace: world->WORLD in while body |
| 7.1b | zoom+inplace: other regions unchanged |
| 7.2  | zoom+template+inplace: template applied |
| 7.3  | archive+zoom+transform+inplace |
| 7.3b | archive: second transform applied |
| 7.3c | archive: goodbye() unchanged |
| 7.4  | archive: sequential in-place edits (name) |
| 7.4b | archive: sequential in-place edits (version) |
| 7.5  | start/end+transform: rename in section |
| 7.5b | start/end+transform: outside section unchanged |
| 7.6  | XML boundary markers: inner content captured |

## Encoding Tests

The test suite validates the 3-tier encoding strategy:

| Tier | Condition | Behaviour |
|------|-----------|-----------|
| I    | Valid UTF-8 input | Output UTF-8, no change |
| II   | Non-UTF-8 (Latin-1) input, ASCII-only transform | Output Latin-1, encoding preserved |
| III  | Non-UTF-8 (Latin-1) input, transform introduces non-Latin-1 chars | Output UTF-8, warning to stderr |

BOM (Byte Order Mark) is automatically stripped from template files to prevent duplication in output.

## Exit Codes

    0  all tests passed
    1  one or more tests failed
