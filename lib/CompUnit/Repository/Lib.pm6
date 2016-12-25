use nqp;

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
sub MAIN(:$name is copy, :$auth, :$ver, *@, *%) {
    shift @*ARGS if $name;
    shift @*ARGS if $auth;
    shift @*ARGS if $ver;
    $name //= \'#dist-name#\';
    my @installations = $*REPO.repo-chain.grep(CompUnit::Repository::Installable);
    my @binaries = flat @installations.map: { .files(\'bin/#name#\', :$name, :$auth, :$ver) };
    unless +@binaries {
        @binaries = flat @installations.map: { .files(\'bin/#name#\') };
        if +@binaries {
            note q:to/SORRY/;
                ===SORRY!===
                No candidate found for \'#name#\' that match your criteria.
                Did you perhaps mean one of these?
                SORRY
            my %caps = :name([\'Distribution\', 12]), :auth([\'Author(ity)\', 11]), :ver([\'Version\', 7]);
            for @binaries -> $dist {
                for %caps.kv -> $caption, @opts {
                    @opts[1] = max @opts[1], ($dist{$caption} // \'\').Str.chars
                }
            }
            note \'  \' ~ %caps.values.map({ sprintf(\'%-*s\', .[1], .[0]) }).join(\' | \');
            for @binaries -> $dist {
                note \'  \' ~ %caps.kv.map( -> $k, $v { sprintf(\'%-*s\', $v.[1], $dist{$k} // \'\') } ).join(\' | \')
            }
        }
        else {
            note "===SORRY!===\nNo candidate found for \'#name#\'.\n";
        }
        exit 1;
    }
    %*ENV<PERL6_PROGRAM_NAME> = $*PROGRAM-NAME;
    exit run($*EXECUTABLE, @binaries[0].hash.<files><bin/#name#>, @*ARGS).exitcode
}';

class CompUnit::Repository::Lib {
    also does CompUnit::Repository::Installable;

    has $!id;
    has $.prefix;
    has %!dist-metas;

    has %!resources;
    has %!loaded;

    has $!cver = nqp::hllize(nqp::atkey(nqp::gethllsym('perl6', '$COMPILER_CONFIG'), 'version'));
    has $!precomp;
    has $!precomp-stores;
    has $!precomp-store;

    method short-id  { 'lib'  }
    method path-spec { 'lib#' }
    method loaded returns Iterable { %!loaded.values }
    method prefix { $!prefix.IO }
    method can-install { self.prefix.w }

    method installed {
        my $distribution-paths := $!prefix.IO.dir.grep(*.d).grep(*.child('META6.json').e);
        my $distributions      := $distribution-paths.map: { Distribution::Path.new($_) };
    }

    method !read-dist($dist-id) {
        my $dist = Rakudo::Internals::JSON.from-json(self.prefix.child($dist-id).child('META6.json').slurp);
        $dist<ver> = $dist<ver> ?? Version.new( ~$dist<ver> ) !! Version.new('0');
        $dist
    }

    multi method candidates(CompUnit::DependencySpecification $spec) {
        nextwith(name => $spec.short-name, auth => $spec.auth-matcher, ver  => $spec.version-matcher);
    }
    multi method candidates(:$name!, :$auth = '', :version(:$ver) = 0) {
        gather for self.installed -> $dist {
            next unless any($name eq $dist.meta<name>, |($dist.meta<provides><<$name>>:exists));
            next if ?$auth and $dist.meta<auth> !~~ $auth;
            next if ?$ver  and $dist.meta<ver version>.first(*.defined) !~~ $ver;
            take $dist;
        }
    }

    method need(
        CompUnit::DependencySpecification  $spec,
        CompUnit::PrecompilationRepository $precomp        = self.precomp-repository(),
        CompUnit::PrecompilationStore     :@precomp-stores = self!precomp-stores(),
    )
        returns CompUnit:D
    {
        if self.candidates($spec)[0] -> $dist {
            my $dist-id = $dist.prefix.basename;
            return %!loaded{~$spec} if %!loaded{~$spec}:exists;

            # XXX: $spec.short-name check is not good and should be removed
            my $load-path := $dist<source>
                ?? $dist.prefix.child($dist<source>)
                !! first *.e,
                    $dist.prefix.child($dist<provides>{~$spec}),
                    $dist.prefix.child($dist<provides>{$spec.short-name});
            my $loader = IO::Path.new(path => $load-path, :CWD($dist.prefix));
            my $*RESOURCES  = Distribution::Resources.new(:repo(self), :$dist-id);
            my $id          = $loader.basename;
            my $repo-prefix = self.prefix;
            my $handle      = $precomp.try-load(
                CompUnit::PrecompilationDependency::File.new(
                    :id(CompUnit::PrecompilationId.new($id)),
                    :src($repo-prefix ?? $repo-prefix ~ $loader.relative($.prefix) !! $loader.abspath),
                    :$spec,
                ),
                :source($loader),
                :@precomp-stores,
            );
            my $precompiled = defined $handle;
            $handle //= CompUnit::Loader.load-source-file($loader);

            # xxx: replace :distribution with meta6
            my $compunit = CompUnit.new(
                :$handle,
                :short-name($spec.short-name),
                :version($dist<ver>),
                :auth($dist<auth> // Str),
                :repo(self),
                :repo-id($id),
                :$precompiled,
                :distribution($dist),
            );

            %!loaded{$spec.short-name} //= $compunit;
            return %!loaded{~$spec} = $compunit;
        }

        return self.next-repo.need($spec, $precomp, :@precomp-stores) if self.next-repo;
        X::CompUnit::UnsatisfiedDependency.new(:specification($spec)).throw;
    }

    method resolve(CompUnit::DependencySpecification $spec) returns CompUnit {
        if self.candidates($spec)[0] -> $dist {
            my $dist-id = $dist.prefix.basename;

            # xxx: replace :distribution with meta6
            return CompUnit.new(
                :handle(CompUnit::Handle),
                :short-name($spec.short-name),
                :version($dist<ver>),
                :auth($dist<auth> // Str),
                :repo(self),
                :repo-id($dist<source> // self!read-dist($dist-id)<provides>{$spec.short-name}.values[0]<file>),
                :distribution($dist),
            );
        }
        return self.next-repo.resolve($spec) if self.next-repo;
        Nil
    }


    method resource($dist-id, $key) {
        self.prefix.child($dist-id).child($key);
    }

    method files($name-path, :$name, :$auth, :$ver) {
        gather for self.installed -> $dist {
            my @dist-name-paths = $dist.meta<files>.map(*.&parse-value);
            next if $name-path ~~ none(@dist-name-paths) || !self.candidates(:$name, :$auth, :$ver);
            take $dist.meta;
        }
    }


    my sub parse-value($str-or-kv) {
        do given $str-or-kv {
            when Str  { $_ }
            when Hash { $_.keys[0] }
            when Pair { $_.key     }
        }
    }

    method install(Distribution $distribution, Bool :$force) {
        my $dist = CompUnit::Repository::Distribution.new($distribution);
        fail "$dist already installed" if not $force and $dist.id ~~ self.installed.any;

        my %files = $dist.meta<files>.grep(*.defined).map: -> $link {
            $link ~~ Str ?? ($link => $link) !! ($link.keys[0] => $link.values[0])
        }

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
                    # note("Installing {$name} for {$dist.meta<name>}") if $verbose and $name ne $dist.meta<name>;
                    my $content = $handle.open.slurp-rest(:bin,:close);
                    $destination.spurt($content);
                    $handle.close;
                }

                when /^bin\// {
                    my $withoutext  = $name-path.subst(/\.[exe|bat]$/, '');
                    for '', '-j', '-m' -> $be {
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
        %!dist-metas{$dist.id} = %meta;
        $dist-dir.child('META6.json').spurt: Rakudo::Internals::JSON.to-json(%meta);

        # reset cached id so it's generated again on next access.
        # identity changes with every installation of a dist.
        $!id = Any;
        my $installed-distribution = Distribution::Path.new($dist-dir);
        self!precompile-distribution($installed-distribution);
        return $installed-distribution;
    }

   method !precompile-distribution(Distribution $distribution is copy) {
        my $dist = CompUnit::Repository::Distribution.new($distribution);
        my $precomp    = $*REPO.precomp-repository;
        my $*RESOURCES = Distribution::Resources.new(:repo(self), dist-id => $dist.id);
        my %done;

        my $dist-dir    = self.prefix.child($dist.id) andthen *.mkdir;
        my $sources-dir = $dist-dir.child('lib');

        for $dist.meta<provides>.kv -> $name, $origpath {
            my $id = $dist.meta<files>{$origpath};
            my $source = $sources-dir.child($id);
            if $precomp.may-precomp {
                my $rev-deps-file = ($precomp.store.path($*PERL.compiler.id, $id) ~ '.rev-deps').IO;
                my @rev-deps      = $rev-deps-file.e ?? $rev-deps-file.lines !! ();
                #if %done{$name} { note "(Already did $name)" if $verbose; next }
                #note("Precompiling $name") if $verbose;

                for @rev-deps -> $rev-dep-id {
                    if %done{$rev-dep-id} {
                        #note "(Already did $rev-dep-id)" if $verbose;
                        next;
                    }
                    #note("Precompiling reverse dependency $rev-dep-id") if $verbose;
                    my $rev-dep-source = $sources-dir.child($rev-dep-id);
                    %done{$rev-dep-id} = $precomp.precompile($rev-dep-source, $rev-dep-id, :force) if $source.e;
                }
            }
        }
    }

    method id() {
        my $parts := nqp::list_s;
        my $prefix = self.prefix;
        my $dir  := { .match(/ ^ <.ident> [ <[ ' - ]> <.ident> ]* $ /) }; # ' hl
        my $file := -> str $file {
            nqp::eqat($file,'.pm',nqp::sub_i(nqp::chars($file),3))
            || nqp::eqat($file,'.pm6',nqp::sub_i(nqp::chars($file),4))
        };
        nqp::if(
          $!id,
          $!id,
          ($!id = nqp::if(
            $prefix.e,
            nqp::stmts(
              (my $iter := Rakudo::Internals.DIR-RECURSE(
                $prefix.absolute,:$dir,:$file).iterator),
              nqp::until(
                nqp::eqaddr((my $pulled := $iter.pull-one),IterationEnd),
                nqp::if(
                  nqp::filereadable($pulled)
                    && (my $pio := nqp::open($pulled,'r')),
                  nqp::stmts(
                    nqp::setencoding($pio,'iso-8859-1'),
                    nqp::push_s($parts,nqp::sha1(nqp::readallfh($pio))),
                    nqp::closefh($pio)
                  )
                )
              ),
              nqp::if(
                (my $next := self.next-repo),
                nqp::push_s($parts,$next.id),
              ),
              nqp::sha1(nqp::join('',$parts))
            ),
            nqp::sha1('')
          ))
        )
    }


    ### Precomp stuff

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
