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
    also does CompUnit::Repository::Locally;

    has $!id;
    has %!dist-metas;

    has %!resources;
    has %!loaded;

    has $!cver = nqp::hllize(nqp::atkey(nqp::gethllsym('perl6', '$COMPILER_CONFIG'), 'version'));
    has $!precomp;
    has $!precomp-stores;
    has $!precomp-store;


    # I wonder if `candidates` should be the Recommendation Manager suggested in S22,
    # and be separate from CompUnit *loading* functionality.
    #
    # role CompUnit::RecommendationManager::Default {
    proto method candidates(|) {*}
    multi method candidates(CompUnit::DependencySpecification $spec) {
        self.candidates(name => $spec.short-name, auth => $spec.auth-matcher, ver  => $spec.version-matcher);
    }
    multi method candidates(:$name!, :$auth = '', :version(:$ver) = 0) {
        gather for self.installed -> $distribution {
            next unless any($name eq $distribution.meta<name>, |($distribution.meta<provides><<$name>>:exists));
            next if ?$auth and $distribution.meta<auth> !~~ $auth;
            next if ?$ver  and self!dist-version($distribution) !~~ Version.new($ver);
            take $distribution;
        }
    }
    #}


    method !repo-prefix { "{self.name}#" }
    method !dist-identity($distribution) {
        return "{$distribution.meta<name>}"
            ~  ":ver<{self!dist-version($distribution)}>"
            ~  ":auth<{$distribution.meta<auth> // ''}>"
            ~  ":api<{$distribution.meta<api> // ''}>";
    }
    method !dist-version($distribution) { Version.new(first *.defined, flat $distribution.meta<ver version>, 0) }
    method !read-dist($dist-id) {
        Distribution::Path.new($!prefix.child($dist-id)) but role :: {
            method Str() {
                return "{$.meta<name>}"
                ~ ":ver<{$.meta<ver>   // ''}>"
                ~ ":auth<{$.meta<auth> // ''}>"
                ~ ":api<{$.meta<api>   // ''}>";
            }
            method id { $dist-id }
        }
    }


    method short-id  { 'lib'  }
    method path-spec { 'lib#' }
    method loaded returns Iterable { %!loaded.values }
    method prefix { $!prefix.IO }
    method can-install { self.prefix.w }
    method name(--> Str) { CompUnit::RepositoryRegistry.name-for-repository(self) }
    method installed { $!prefix.IO.dir.grep(*.d).grep(*.child('META6.json').e).map({ self!read-dist(.basename) }) }


    method need(
        CompUnit::DependencySpecification  $spec,
        CompUnit::PrecompilationRepository $precomp        = self.precomp-repository(),
        CompUnit::PrecompilationStore     :@precomp-stores = self!precomp-stores(),
    )
        returns CompUnit:D
    {
        return %!loaded{~$spec} if %!loaded{~$spec}:exists;

        if self.candidates($spec)[0] -> $distribution {
            my $*RESOURCES = Distribution::Resources.new(:repo(self), :dist-id($distribution.id));
            my $source-handle = $distribution.content($distribution.meta<provides>{$spec.short-name});
            my $precomp-handle = $precomp.try-load(
                CompUnit::PrecompilationDependency::File.new(
                    :id(CompUnit::PrecompilationId.new($distribution.id)),
                    :src(~$source-handle.path),
                    :$spec,
                ),
                :source($source-handle.path),
                :@precomp-stores,
            );
            my $compunit = CompUnit.new(
                :handle($precomp-handle // $source-handle),
                :short-name($spec.short-name),
                :version(self!dist-version($distribution)),
                :auth($distribution.meta<auth> // Str),
                :repo(self),
                :repo-id(self.path-spec),
                :precompiled(defined $precomp-handle),
                :$distribution,
            );

            return %!loaded{~$spec} //= $compunit;
        }

        return self.next-repo.need($spec, $precomp, :@precomp-stores) if self.next-repo;
        X::CompUnit::UnsatisfiedDependency.new(:specification($spec)).throw;
    }

    method resolve(CompUnit::DependencySpecification $spec) returns CompUnit {
        if self.candidates($spec)[0] -> $distribution {
            return CompUnit.new(
                :handle(CompUnit::Handle),
                :short-name($spec.short-name),
                :version(self!dist-version($distribution)),
                :auth($distribution.meta<auth> // Str),
                :repo(self),
                :repo-id(self.path-spec),
                :$distribution,
            );
        }
        return self.next-repo.resolve($spec) if self.next-repo;
        Nil
    }


    method resource($dist-id, $key) {
        self.prefix.child($dist-id).child("resources/$key");
    }

    method files($name-path, *%spec [:$name, :$auth, :$ver]) {
        my $distributions := $name
            ?? self.candidates(|%spec)
            !! self.installed
                .grep({!$auth || .meta<auth> ~~ $auth})
                .grep({!$ver  || Version.new(.meta<ver version>.first(*.defined)) ~~ Version.new($ver)});
        gather for $distributions -> $dist {
            my @dist-name-paths = $dist.meta<files>.map(*.&parse-value);
            next if $name-path ~~ none(@dist-name-paths);
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

    method install(Distribution $distribution, Bool :$force, Bool :$precompile = True) {
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
        %!dist-metas{$dist.id} = %meta;
        $dist-dir.child('META6.json').spurt: Rakudo::Internals::JSON.to-json(%meta);

        # reset cached id so it's generated again on next access.
        # identity changes with every installation of a dist.
        $!id = Any;
        my $installed-distribution = Distribution::Path.new($dist-dir);
        self!precompile-distribution($installed-distribution) if ?$precompile;
        return $installed-distribution;
    }

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
                my $id = CompUnit::PrecompilationId.new($dist.id);
                $precomp.store.delete($compiler-id, $id);
            }

            for %provides.kv -> $name, $name-path {
                my $id = CompUnit::PrecompilationId.new($dist.id);
                my $source-file = $distribution.prefix.child($name-path);

                if %done{$id} {
                    #note "(Already did $id)" if $verbose;
                    next;
                }
                #note("Precompiling $id ($name)") if $verbose;
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
