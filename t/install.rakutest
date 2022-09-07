use Test;
plan 3;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$*PROGRAM.parent(2).child('resources/test-dists').absolute}";


my $distribution-path = $*PROGRAM.IO.parent(2).child('resources/test-dists').child('CECF2DDE6951E23F6F0E469FC3A3006444B8FFB3');
my $distribution      = Distribution::Path.new($distribution-path);

subtest 'Skip precompiling during installation' => {
    my $install-to-path = $*TMPDIR.child('raku-cur-lib').child(time).child((^1000000).pick) andthen *.mkdir;
    my $install-to-repo = CompUnit::Repository::Lib.new(prefix => $install-to-path.absolute);
    lives-ok { $install-to-repo.install($distribution, :!precompile) }, "Installed to $install-to-path";
    lives-ok { $install-to-repo.uninstall($distribution) }, "Uninstalled from $install-to-path";
}

subtest 'Attempt precompiling during installation with no external dependencies' => {
    my $dist = Distribution::Hash.new({ meta => version => '*', auth => 'github:ugexe', name => 'Acme-Foo2', provides => { Acme => 'lib/Acme/Foo.pm6' } }, prefix => $distribution-path);
    my $install-to-path = $*TMPDIR.child('raku-cur-lib').child(time).child((^1000000).pick) andthen *.mkdir;
    my $install-to-repo = CompUnit::Repository::Lib.new(prefix => $install-to-path.absolute);
    todo('NYI or Precompilation does not work for non-core repos... not sure');
    lives-ok { $install-to-repo.install($dist) }
}

subtest 'Attempt precompiling during installation' => {
    my $install-to-path = $*TMPDIR.child('raku-cur-lib').child(time).child((^1000000).pick) andthen *.mkdir;
    my $install-to-repo = CompUnit::Repository::Lib.new(prefix => $install-to-path.absolute);
    todo('NYI or Precompilation does not work for non-core repos... not sure');
    lives-ok { $install-to-repo.install($distribution) }
}

done-testing;
