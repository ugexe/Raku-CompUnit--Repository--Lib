use Test;
plan 5;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$*PROGRAM.parent(2).child('resources/test-dists').absolute}";


subtest 'name-path only' => {
    ok  $*REPO.repo-chain[0].files("bin/acme-foo-script");
    nok $*REPO.repo-chain[0].files("bin/xxx");
}

subtest 'name-path and distribution name' => {
    ok  $*REPO.repo-chain[0].files("bin/acme-foo-script", name => "Acme-Foo");
    nok $*REPO.repo-chain[0].files("bin/acme-foo-script", name => "xxx");
}

subtest 'name-path and distribution auth' => {
    ok  $*REPO.repo-chain[0].files("bin/acme-foo-script", auth => "github:ugexe");
    nok $*REPO.repo-chain[0].files("bin/acme-foo-script", auth => "github:xxx");
}

subtest 'name-path and distribution ver' => {
    ok  $*REPO.repo-chain[0].files("bin/acme-foo-script", ver => "*");
}

subtest 'name-path and distribution name/auth/ver' => {
    ok  $*REPO.repo-chain[0].files("bin/acme-foo-script", name => "Acme-Foo", auth => "github:ugexe", ver => "*");
    nok $*REPO.repo-chain[0].files("bin/xxx", name => "Acme-Foo", auth => "github:ugexe", ver => "*");
}

done-testing;
