use v6;
use Test;
plan 2;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$*PROGRAM.parent.child('test-libs').absolute}";

subtest {
    {
        dies-ok { ::("Acme::Foo")<&acme-foo-source-file>() };
    }
    {
        use-ok("Acme::Foo"), 'module use-d ok';
    }
}, 'require module with no external dependencies';

subtest {
    {
        dies-ok { ::("Acme::Depends::On::Acme::Foo")<&dependency-source-file>() };
    }
    {
        use-ok("Acme::Depends::On::Acme::Foo"), 'module use-d ok';
    }
}, 'require modules with external dependency chain';

done-testing;
