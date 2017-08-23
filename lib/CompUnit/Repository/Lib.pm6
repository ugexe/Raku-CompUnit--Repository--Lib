use nqp;

my $RMD = $*RAKUDO_MODULE_DEBUG;

my $windows_wrapper = '@rem = \'--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
#perl# "%~dpn0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
#perl# "%~dpn0" %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem \';
__END__
:endofperl
';
my $perl_wrapper = '#!/usr/bin/env #perl#
sub MAIN(:$name, :$auth, :$ver, *@, *%) {
    CompUnit::RepositoryRegistry.run-script("#name#", :$name, :$auth, :$ver);
}';

class CompUnit::Repository::Lib {
    also does CompUnit::Repository::Installable;
    also does CompUnit::Repository::Locally;

    has %!loaded; # cache compunit lookup for self.need(...)
    has %!seen;   # cache distribution lookup for self!matching-dist(...)
    has $!id;
    has $!name;

    has $!cver = nqp::hllize(nqp::atkey(nqp::gethllsym('perl6', '$COMPILER_CONFIG'), 'version'));
    has $!precomp;
    has $!precomp-stores;
    has $!precomp-store;

    my $verbose := nqp::getenvhash<RAKUDO_LOG_PRECOMP>;

    submethod BUILD(:$!prefix, :$!lock, :$!WHICH, :$!next-repo, Str :$!name = 'xxx' --> Nil) {
        CompUnit::RepositoryRegistry.register-name($!name, self);
    }

    proto method files(|) {*}
    multi method files($file, Str:D :$name!, :$auth, :$ver, :$api) {
        my $spec = CompUnit::DependencySpecification.new(
            short-name      => $name,
            auth-matcher    => $auth // True,
            version-matcher => $ver  // True,
            api-matcher     => $api  // True,
        );

        with self.candidates($spec) {
            my $matches := $_.grep: { .meta<files>{$file}:exists }

            my $absolutified-metas := $matches.map: {
                my $meta      = $_.meta;
                $meta<source> = $meta<files>{$file}.IO;
                $meta;
            }

            return $absolutified-metas.grep(*.<source>.e);
        }
    }
    multi method files($file, :$auth, :$ver, :$api) {
        my $spec = CompUnit::DependencySpecification.new(
            short-name      => $file,
            auth-matcher    => $auth // True,
            version-matcher => $ver  // True,
            api-matcher     => $api  // True,
        );

        with self.candidates($spec) {
            my $absolutified-metas := $_.map: {
                my $meta      = $_.meta;
                $meta<source> = $meta<files>{$file}.IO;
                $meta;
            }

            return $absolutified-metas.grep(*.<source>.e);
        }
    }

    proto method candidates(|) {*}
    multi method candidates(Str:D $name, :$auth, :$ver, :$api) {
        return samewith(CompUnit::DependencySpecification.new(
            short-name      => $name,
            auth-matcher    => $auth // True,
            version-matcher => $ver  // True,
            api-matcher     => $api  // True,
        ));
    }
    multi method candidates(CompUnit::DependencySpecification $spec) {
        return Empty unless $spec.from eq 'Perl6';

        my $version-matcher = ($spec.version-matcher ~~ Bool)
            ?? $spec.version-matcher
            !! Version.new($spec.version-matcher);
        my $api-matcher = ($spec.api-matcher ~~ Bool)
            ?? $spec.api-matcher
            !! Version.new($spec.api-matcher);

        my $matching-dists := self.installed.grep: {
            my $name-matcher = any(
                $_.meta<name>,
                |$_.meta<provides>.keys,
                |$_.meta<provides>.values.map(*.&parse-value),
                |$_.meta<files>.hash.keys,
            );

            if $_.meta<provides>{$spec.short-name}
            // $_.meta<files>{$spec.short-name} -> $source
            {
                $_.meta<source> = $_.prefix.child(parse-value($source)).absolute;
            }

            so $spec.short-name eq $name-matcher
                and $_.meta<auth> ~~ $spec.auth-matcher
                and $_.meta<ver>  ~~ $version-matcher
                and $_.meta<api>  ~~ $api-matcher
        }

        return $matching-dists;
    }

    method !matching-dist(CompUnit::DependencySpecification $spec) {
        return %!seen{~$spec} if %!seen{~$spec}:exists;

        my $dist = self.candidates($spec).head;

        $!lock.protect: {
            return %!seen{~$spec} //= $dist;
        }
    }

    my class Distribution::Lib is Distribution::Path {
        has $!checksum;

        submethod TWEAK() {
            self.meta<ver> = Version.new(self.meta<ver> // self.meta<version> // 0);
            self.meta<files> = self.meta<files>.hash;
            # self.meta<api> = Version.new(self.meta<api> // 0); # changes self.Str and self.id
        }

        method Str() {
            return "{$.meta<name>}"
            ~ ":ver<{$.meta<ver>   // ''}>"
            ~ ":auth<{$.meta<auth> // ''}>"
            ~ ":api<{$.meta<api>   // ''}>";
        }

        method id() {
            return nqp::sha1(self.Str);
        }

        # https://github.com/rakudo/rakudo/blob/faea193ec9563f8425a2a59cc4190068adb41c6e/src/core/CompUnit/Repository/FileSystem.pm#L60
        method checksum {
            my $parts := nqp::list_s;
            my $prefix = self.prefix;
            my $dir  := { .match(/ ^ <.ident> [ <[ ' - ]> <.ident> ]* $ /) }; # ' hl
            my $file := -> str $file {
                nqp::eqat($file,'.pm',nqp::sub_i(nqp::chars($file),3))
                || nqp::eqat($file,'.pm6',nqp::sub_i(nqp::chars($file),4))
            };
            nqp::if(
              $!checksum,
              $!checksum,
              ($!checksum = nqp::if(
                $prefix.e,
                nqp::stmts(
                  (my $iter := Rakudo::Internals.DIR-RECURSE(
                    $prefix.absolute,:$dir,:$file).iterator),
                  nqp::until(
                    nqp::eqaddr((my $pulled := $iter.pull-one),IterationEnd),
                    nqp::if(
                      nqp::filereadable($pulled),
                      nqp::push_s($parts,nqp::sha1(slurp($pulled, :enc<iso-8859-1>))),
                    )
                  ),
                  nqp::sha1(nqp::join('',$parts))
                ),
                nqp::sha1('')
              ))
            )
        }
    }

    # When new module is installed $!id is set to Any so that this gets re-run
    method id { $!id //= self.installed.map(*.id).sort.reduce({ nqp::sha1($^a, $^b) }) }

    method short-id { 'lib' }
    method path-spec { "CompUnit::Repository::Lib#name({$!name // 'wut'})#{self.prefix.absolute}" }

    method repo-id($distribution) { self.path-spec ~ '/' ~ $distribution.id }

    method loaded returns Iterable { %!loaded.values }
    method prefix { $!prefix.IO }
    method can-install { self.prefix.w }
    method installed { $!prefix.IO.dir.grep(*.d).grep(*.child('META6.json').e).map({ self!read-dist($_.basename) }) }

    method !content-address($distribution, $name-path) { nqp::sha1($name-path ~ $distribution.id) }
    method !read-dist($dist-id) { Distribution::Lib.new( $!prefix.child($dist-id) ) }

    method need(
        CompUnit::DependencySpecification  $spec,
        CompUnit::PrecompilationRepository $precomp        = self.precomp-repository(),
        CompUnit::PrecompilationStore     :@precomp-stores = self!precomp-stores(),
    )
        returns CompUnit:D
    {
        $RMD("[need] -> {$spec.perl}") if $RMD;
        return %!loaded{~$spec} if %!loaded{~$spec}:exists;
        $RMD("[need] not cached - keep looking...") if $RMD;

        with self!matching-dist($spec) {
            my $id = self!content-address($_, $spec.short-name);
            return %!loaded{$id} if %!loaded{$id}:exists;

            X::CompUnit::UnsatisfiedDependency.new(:specification($spec)).throw
                unless .meta<source>;

            my $name-path     = parse-value($_.meta<provides>{$spec.short-name});
            my $source-path   = $_.meta<source>.IO;
            my $source-handle = CompUnit::Loader.load-source-file($source-path);

            $RMD("[need] name-path:{$name-path}=$source-path source-handle:{$source-handle.perl}") if $RMD;

            my $*RESOURCES = Distribution::Resources.new(:repo(self), :dist-id($_.id));
            my $precomp-handle = $precomp.try-load(
                CompUnit::PrecompilationDependency::File.new(
                    :id(CompUnit::PrecompilationId.new($id)),
                    :src($source-path.absolute),
                    :checksum($_.meta<checksum>:exists ?? $_.meta<checksum> !! Str),
                    :$spec,
                ),
                :source($source-path),
                :@precomp-stores,
            );
            my $compunit = CompUnit.new(
                :handle($precomp-handle // $source-handle),
                :short-name($spec.short-name),
                :version($_.meta<ver>),
                :auth($_.meta<auth> // Str),
                :repo(self),
                :repo-id($id),
                :precompiled(defined $precomp-handle),
                :distribution($_),
            );

            $RMD("[need] taking compunit {$compunit // 'WTF ???'}") if $RMD;
            return %!loaded{~$spec} //= $compunit;
        }

        return self.next-repo.need($spec, $precomp, :@precomp-stores) if self.next-repo;
        X::CompUnit::UnsatisfiedDependency.new(:specification($spec)).throw;
    }

    method resolve(CompUnit::DependencySpecification $spec) returns CompUnit {
        with self!matching-dist($spec) {
            return CompUnit.new(
                :handle(CompUnit::Handle),
                :short-name($spec.short-name),
                :version($_.meta<ver>),
                :auth($_.meta<auth> // Str),
                :repo(self),
                :repo-id(self!content-address($_, $spec.short-name)),
                :distribution($_),
            );
        }

        return self.next-repo.resolve($spec) if self.next-repo;
        Nil
    }


    method resource($dist-id, $key) {
        self.prefix.child($dist-id).child("$key");
    }

    my sub parse-value($str-or-kv) {
        do given $str-or-kv {
            when Str  { $_ }
            when Hash { $_.keys[0] }
            when Pair { $_.key     }
        }
    }

    method install(Distribution $distribution, Bool :$force, Bool :$precompile = True) {
        my $dist = CompUnit::Repository::Distribution.new($distribution);
        fail "$dist already installed" if not $force and $dist.id ~~ self.installed.map(*.id).any;

        my %files = $dist.meta<files>.grep(*.defined).map({ $_ ~~ Str ?? ($_ => $_) !! ($_.keys[0] => $_.values[0]) }).hash;

        my @*MODULES;
        my $dist-dir        = self.prefix.child($dist.id) andthen *.mkdir;
        my $sources-dir     = $dist-dir.child('lib');
        my $resources-dir   = $dist-dir.child('resources');
        my $bin-dir         = $dist-dir.child('bin');
        my $bin-wrapper-dir = self.prefix.child('bin');
        my $is-win          = Rakudo::Internals.IS-WIN;

        my $implicit-files := $dist.meta<provides>.values;
        my $explicit-files := $dist.meta<files>;
        my $all-files      := unique map { $_ ~~ Str ?? $_ !! $_.keys[0] },
            grep *.defined, $implicit-files.Slip, $explicit-files.Slip;

        for @$all-files -> $name-path {
            # xxx: should really handle hash leaf nodes like Distribution does
            state %pm6-path2name = $dist.meta<provides>.antipairs;
            state @provides = $dist.meta<provides>.values; # only meant for use in a regex /^@provides/

            given $name-path {
                my $handle := $dist.content($name-path);
                my $destination = $dist-dir.child($name-path) andthen *.parent.mkdir;

                when /^@provides$/ {
                    my $name = %pm6-path2name{$name-path};
                    note("Installing {$name} for {$dist.meta<name>}") if $verbose and $name ne $dist.meta<name>;
                    my $content = $handle.open.slurp-rest(:bin,:close);
                    $destination.spurt($content);
                    $handle.close;
                }

                when /^bin\// {
                    my $withoutext  = $name-path.subst(/\.[exe|bat]$/, '');
                    for '', '-j', '-m' -> $be {
                        mkdir $.prefix.child("$withoutext$be").IO.parent;
                        $.prefix.child("$withoutext$be").IO.spurt:
                            $perl_wrapper.subst('#name#', $name-path.IO.basename, :g).subst('#perl#', "perl6$be").subst('#dist-name#', $dist.meta<name>);
                        if $is-win {
                            $.prefix.child("$withoutext$be.bat").IO.spurt:
                                $windows_wrapper.subst('#perl#', "perl6$be", :g);
                        }
                        else {
                            $.prefix.child("$withoutext$be").IO.chmod(0o755);
                        }
                    }
                    my $content = $handle.open.slurp-rest(:bin, :close);
                    $destination.spurt($content);
                    $handle.close;
                }

                when /^resources\/$<subdir>=(.*)/ {
                    my $subdir = $<subdir>; # maybe do something with libraries

                    my $content = $handle.open.slurp-rest(:bin, :close);
                    $destination.spurt($content);
                    $handle.close;
                }
            }
        }

        my %meta = %($dist.meta);
        $dist-dir.child('META6.json').spurt: Rakudo::Internals::JSON.to-json(%meta);

        # reset cached id so it's generated again on next access.
        # identity changes with every installation of a dist.
        $!id = Any;
        my $installed-distribution = Distribution::Path.new($dist-dir);
        self!precompile-distribution($installed-distribution) if ?$precompile;
        return $installed-distribution;
    }

    ### Precomp stuff beyond this point

   method !precompile-distribution(Distribution $distribution is copy) {
        my $dist = CompUnit::Repository::Distribution.new($distribution);
        my $precomp    = $*REPO.precomp-repository;
        my $*RESOURCES = Distribution::Resources.new(:repo(self), dist-id => $dist.id);
        my %done;

        my $dist-dir    = self.prefix.child($dist.id) andthen *.mkdir;
        my $sources-dir = $dist-dir.child('lib');

        {
            my $head = $*REPO;
            PROCESS::<$REPO> := self; # Precomp files should only depend on downstream repos
            my $precomp = $*REPO.precomp-repository;
            my $*RESOURCES = Distribution::Resources.new(:repo(self), dist-id => $dist.id);
            my %done;
            my %provides = $dist.meta<provides>;

            my $compiler-id = CompUnit::PrecompilationId.new($*PERL.compiler.id);
            for %provides.kv -> $name, $name-path {
                my $id = CompUnit::PrecompilationId.new(self!content-address($dist, $name-path));
                $precomp.store.delete($compiler-id, $id);
            }

            for %provides.kv -> $name, $name-path {
                my $id = CompUnit::PrecompilationId.new(self!content-address($dist, $name-path));
                my $source-file = $distribution.prefix.child($name-path);

                if %done{$id} {
                    note "(Already did $id)" if $verbose;
                    next;
                }
                note("Precompiling $id ($name)") if $verbose;
                $precomp.precompile(
                    $source-file,
                    $id,
                    :source-name("$source-file ($name)"),
                );
                %done{$id} = 1;
            }
            PROCESS::<$REPO> := $head;
        }
    }

    method !precomp-stores() {
        $!precomp-stores //= Array[CompUnit::PrecompilationStore].new(
            self.repo-chain.map(*.precomp-store).grep(*.defined)
        )
    }

    method precomp-store() returns CompUnit::PrecompilationStore {
        $!precomp-store //= CompUnit::PrecompilationStore::File.new(
            :prefix(self.prefix.child('.precomp')),
        )
    }

    method precomp-repository() returns CompUnit::PrecompilationRepository {
        $!precomp := CompUnit::PrecompilationRepository::Default.new(
            :store(self.precomp-store),
        ) unless $!precomp;
        $!precomp
    }
}
