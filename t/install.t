use v6;
use Test;
plan 1;

use CompUnit::Repository::Lib;

my $distribution-path = $?FILE.IO.parent.child('test-libs').dir.grep({.basename !~~ /^\.precomp/}).sort.head;
my $distribution      = Distribution::Path.new($distribution-path);
my $install-to-path = $*TMPDIR.child('perl6-cur-lib').child(time).child((^1000000).pick) andthen *.mkdir;
my $install-to-repo = CompUnit::Repository::Lib.new(prefix => $install-to-path);

lives-ok { $install-to-repo.install($distribution) }
