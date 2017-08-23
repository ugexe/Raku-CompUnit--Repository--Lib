use v6;
use Test;
plan 5;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$*PROGRAM.parent.child('test-libs')}";


subtest {
    ok  $*REPO.repo-chain[0].files("bin/acme-foo-script");
    nok $*REPO.repo-chain[0].files("bin/xxx");
}, 'name-path only';

subtest {
    ok  $*REPO.repo-chain[0].files("bin/acme-foo-script", name => "Acme-Foo");
    nok $*REPO.repo-chain[0].files("bin/acme-foo-script", name => "xxx");
}, 'name-path and distribution name';

subtest {
    ok  $*REPO.repo-chain[0].files("bin/acme-foo-script", auth => "github:ugexe");
    nok $*REPO.repo-chain[0].files("bin/acme-foo-script", auth => "github:xxx");
}, 'name-path and distribution auth';

subtest {
    ok  $*REPO.repo-chain[0].files("bin/acme-foo-script", ver => "*");
}, 'name-path and distribution ver';

subtest {
    ok  $*REPO.repo-chain[0].files("bin/acme-foo-script", name => "Acme-Foo", auth => "github:ugexe", ver => "*");
    nok $*REPO.repo-chain[0].files("bin/xxx", name => "Acme-Foo", auth => "github:ugexe", ver => "*");
}, 'name-path and distribution name/auth/ver';

done-testing;
