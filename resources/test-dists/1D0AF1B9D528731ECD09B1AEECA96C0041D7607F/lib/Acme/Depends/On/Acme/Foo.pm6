unit module Acme::Depends::On::Acme::Foo;
use Acme::Foo:auth<github:ugexe>:ver<0>;;
use Acme::Depends::On::Acme::Foo::Resources:auth<github:ugexe>:ver<0>;

our sub dependency-source-file is export { acme-foo-source-file() }

our sub dependency-resources is export { get-resources() }
