use v6;
use Test;
plan 3;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$*PROGRAM.parent.child('test-libs')}";

my $distribution-path = $*PROGRAM.IO.parent.child('test-libs').child('CECF2DDE6951E23F6F0E469FC3A3006444B8FFB3');
my $distribution      = Distribution::Path.new($distribution-path);

subtest {
    my $install-to-path = $*TMPDIR.child('perl6-cur-lib').child(time).child((^1000000).pick) andthen *.mkdir;
    my $install-to-repo = CompUnit::Repository::Lib.new(prefix => $install-to-path.absolute);
    lives-ok { $install-to-repo.install($distribution, :!precompile) }, "Installed to $install-to-path";
    lives-ok { $install-to-repo.uninstall($distribution) }, "Uninstalled from $install-to-path";
}, 'Skip precompiling during installation';

subtest {
    my $dist = Distribution::Hash.new({ meta => perl => '6.c', version => '*', auth => 'github:ugexe', name => 'Acme-Foo2', provides => { Zef => 'lib/Acme/Foo.pm6' } }, prefix => $distribution-path);
    my $install-to-path = $*TMPDIR.child('perl6-cur-lib').child(time).child((^1000000).pick) andthen *.mkdir;
    my $install-to-repo = CompUnit::Repository::Lib.new(prefix => $install-to-path.absolute);
    lives-ok { $install-to-repo.install($dist) }
}, 'Attempt precompiling during installation with no external dependencies';

subtest {
    my $install-to-path = $*TMPDIR.child('perl6-cur-lib').child(time).child((^1000000).pick) andthen *.mkdir;
    my $install-to-repo = CompUnit::Repository::Lib.new(prefix => $install-to-path.absolute);
    lives-ok { $install-to-repo.install($distribution) }
}, 'Attempt precompiling during installation';

done-testing;
