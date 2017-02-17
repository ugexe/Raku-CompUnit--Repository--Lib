use Test;
plan 2;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$?FILE.IO.parent.child('test-libs')}";


my $matching-spec = CompUnit::DependencySpecification.new(
    short-name      => 'Zef::Client',
    auth-matcher    => 'github:ugexe',
    version-matcher => '*',
);
my $missing-spec = CompUnit::DependencySpecification.new(
    short-name      => 'Zef::Client',
    auth-matcher    => 'cpan:ugexe',
    version-matcher => '*',
);


ok  $*REPO.repo-chain[0].resolve($matching-spec);
nok $*REPO.repo-chain[0].resolve($missing-spec);
