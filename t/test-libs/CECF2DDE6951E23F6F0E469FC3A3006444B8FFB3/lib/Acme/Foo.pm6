unit module Acme::Foo;
use Acme::Foo::Resources:auth<github:ugexe>:ver<0>;;

our sub acme-foo-source-file is export { $*PROGRAM.absolute }

our sub acme-foo-resources is export { Acme::Foo::Resources::resources() }
