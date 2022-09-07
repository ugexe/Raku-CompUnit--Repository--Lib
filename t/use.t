use Test;
plan 2;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$*PROGRAM.parent(2).child('resources/test-dists').absolute}";


subtest 'require module with no external dependencies' => {
    {
        dies-ok { ::("Acme::Foo") };
    }
    {
        use-ok("Acme::Foo"), 'module use-d ok';
    }
}

subtest 'require modules with external dependency chain' => {
    {
        dies-ok { ::("Acme::Depends::On::Acme::Foo") };
    }
    {
        use-ok("Acme::Depends::On::Acme::Foo"), 'module use-d ok';
    }
}

done-testing;
