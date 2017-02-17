use v6;
use Test;
plan 2;

use CompUnit::Repository::Lib;
use lib "CompUnit::Repository::Lib#{$?FILE.IO.parent.child('test-libs')}";


subtest {
    {
        nok '$!dist' ~~ any( ::("Candidate").^attributes>>.name ), 'module not yet loaded';
    }
    {
        lives-ok { require ::("Zef") },                            'module require-d ok';
        ok '$!dist' ~~ any( ::("Candidate").^attributes>>.name ),  'module is accessable';
    }
}, 'require module with no dependencies';

subtest {
    {
        nok '$!config' ~~ any( ::("Zef::Client").^attributes>>.name ), 'module not yet loaded';
    }
    {
        lives-ok { require ::("Zef::Client") },                        'module require-d ok';
        ok '$!config' ~~ any( ::("Zef::Client").^attributes>>.name ),  'module loaded';
    }
}, 'require modules with multi-level dependency chain';
