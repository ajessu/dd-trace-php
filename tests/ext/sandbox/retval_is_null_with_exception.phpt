--TEST--
The return value is null when an exception is thrown in the original call
--DESCRIPTION--
We enable debug mode to ensure this does not raise an "Undefined variable" E_NOTICE in the tracing closure
https://github.com/DataDog/dd-trace-php/issues/788
--SKIPIF--
<?php if (PHP_VERSION_ID < 50500) die('skip: PHP 5.4 not supported'); ?>
--ENV--
DD_TRACE_DEBUG=1
--FILE--
<?php
use DDTrace\SpanData;

function foo()
{
    throw new Exception('Oops!');
    return 42;
}

dd_trace_function('foo', function (SpanData $span, array $args, $retval, $ex) {
    var_dump($ex instanceof Exception);
    var_dump($retval);
});

try {
    foo();
} catch (Exception $e) {
    echo $e->getMessage() . PHP_EOL;
}
?>
--EXPECT--
bool(true)
NULL
Oops!
