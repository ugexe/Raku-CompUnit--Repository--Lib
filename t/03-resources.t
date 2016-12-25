use v6;
use Test;
plan 1;

use CompUnit::Repository::Lib;

use lib "CompUnit::Repository::Lib#{$?FILE.IO.parent.child('test-libs')}";


subtest {
    use-ok('Zef::Config');
    ok Zef::Config::guess-path.?ends-with(".json"), '%?RESOURCES<config.json>';
}, 'access a the resources of a distribution';