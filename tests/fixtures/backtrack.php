<?php

class a {
    function foo($x) {
        # start cmd1
        cmd1($x);
    }

    function foo($x) {
        # start cmd2
        cmd2($x);
    }

    function bar() {
        # This has multiple () and {} patterns
        if (x) {
            nested_call();
        }
    }
}

# Another context with foo() to test scope
function standalone_foo() {
    echo "hello";
}
