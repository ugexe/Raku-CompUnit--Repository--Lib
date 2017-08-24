use v6;
use Test;
plan 2;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$*PROGRAM.parent.child('test-libs').absolute}";

subtest {
    {
        dies-ok { ::("Acme::Foo")<&acme-foo-source-file>() };
        lives-ok { require ::("Acme::Foo") <&acme-foo-source-file> }, 'module require-d ok';
    }
    {
        require ::("Acme::Foo") <&acme-foo-source-file>;
        ok acme-foo-source-file().IO.e, 'module is accessable';
    }
}, 'require module with no external dependencies';

subtest {
    {
        dies-ok { ::("Acme::Depends::On::Acme::Foo")<&dependency-source-file>() };
        lives-ok { require ::("Acme::Depends::On::Acme::Foo") <&dependency-source-file &dependency-resources>}, 'module require-d ok';
    }
    {
        require ::("Acme::Depends::On::Acme::Foo") <&dependency-source-file &dependency-resources>;
        ok dependency-source-file().IO.e, 'module is accessable';
        #ok dependency-resources().<config.json>.IO.e, 'module resource is accessable';
    }
}, 'require modules with external dependency chain';

done-testing;
