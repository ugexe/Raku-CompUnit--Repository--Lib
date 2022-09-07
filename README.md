## CompUnit::Repository::Lib

Load modules and install modules to the development style lib/original-path

## Synopsis

    use CompUnit::Repository::Lib;

    use lib "CompUnit::Repository::Lib#{$*CWD/resources/test-dists}";

    require <Acme::Foo>;        # `require` by name
    use Acme::Foo;              # `use` by name

See: L<tests|https://github.com/ugexe/Perl6-CompUnit--Repository--Lib/blob/master/t>
