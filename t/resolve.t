use Test;
plan 2;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$*PROGRAM.parent.child('test-libs')}";


my $matching-spec = CompUnit::DependencySpecification.new(
    short-name      => 'Acme::Foo',
    auth-matcher    => 'github:ugexe',
    version-matcher => '0',
);
my $missing-spec = CompUnit::DependencySpecification.new(
    short-name      => 'Acme::Foo',
    auth-matcher    => 'cpan:ugexe',
    version-matcher => '666',
);


ok  $*REPO.repo-chain[0].resolve($matching-spec);
nok $*REPO.repo-chain[0].resolve($missing-spec);
