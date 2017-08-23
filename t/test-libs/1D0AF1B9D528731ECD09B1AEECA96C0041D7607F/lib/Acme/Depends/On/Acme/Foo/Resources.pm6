unit module Acme::Depends::On::Acme::Foo::Resources;
use Acme::Foo::Resources:auth<github:ugexe>:ver<0>;

our sub resources { Acme::Foo::Resources::resources }
