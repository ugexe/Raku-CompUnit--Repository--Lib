use v6;
use Test;
plan 2;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$?FILE.IO.parent.child('test-libs')}";


my $distribution-path = $?FILE.IO.parent.child('test-libs').dir.grep({.basename !~~ /^\.precomp/}).sort.head;
my $distribution      = Distribution::Path.new($distribution-path);

subtest {
    my $install-to-path = $*TMPDIR.child('perl6-cur-lib').child(time).child((^1000000).pick) andthen *.mkdir;
    my $install-to-repo = CompUnit::Repository::Lib.new(prefix => $install-to-path.absolute);
    lives-ok { $install-to-repo.install($distribution, :!precompile) }, "Installed to $install-to-path";
}, 'Skip precompiling during installation';

subtest {
    my $dist = Distribution::Hash.new({ meta => perl => '6.c', version => '*', auth => 'github:ugexe', name => 'ZeffeZ', provides => { Zef => 'lib/Zef.pm6' } }, prefix => $distribution-path);
    my $install-to-path = $*TMPDIR.child('perl6-cur-lib').child(time).child((^1000000).pick) andthen *.mkdir;
    my $install-to-repo = CompUnit::Repository::Lib.new(prefix => $install-to-path.absolute);
    lives-ok { $install-to-repo.install($dist) }
}, 'Attempt precompiling during installation with no dependencies (internal or external)';

subtest {
    my $install-to-path = $*TMPDIR.child('perl6-cur-lib').child(time).child((^1000000).pick) andthen *.mkdir;
    my $install-to-repo = CompUnit::Repository::Lib.new(prefix => $install-to-path.absolute);
    lives-ok { $install-to-repo.install($distribution) }
}, 'Attempt precompiling during installation';
