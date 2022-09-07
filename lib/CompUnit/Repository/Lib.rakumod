use v6;
use nqp;

my $RMD = $*RAKUDO_MODULE_DEBUG;

my $windows_wrapper = '@rem = \'--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
#raku# "%~dpn0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofraku
:WinNT
#raku# "%~dpn0" %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofraku
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofraku
@rem \';
__END__
:endofraku
';
my $raku_wrapper = '#!/usr/bin/env #raku#
sub MAIN(:$name, :$auth, :$ver, *@, *%) {
    CompUnit::RepositoryRegistry.run-script("#name#", :$name, :$auth, :$ver);
}';

my sub parse-value($str-or-kv) {
    do given $str-or-kv {
        when Str  { $_ }
        when Hash { $_.keys[0] }
        when Pair { $_.key     }
    }
}

class CompUnit::Repository::Lib {
    also does CompUnit::Repository::Installable;
    also does CompUnit::Repository::Locally;

    has %!loaded; # cache compunit lookup for self.need(...)
    has %!seen;   # cache distribution lookup for self!matching-dist(...)
    has $!id;
    has $!name;
    has $!lock;

    has $!cver = nqp::hllize(nqp::atkey(nqp::gethllsym('raku', '$COMPILER_CONFIG'), 'version'));
    has $!precomp;
    has $!precomp-stores;
    has $!precomp-store;

    my $verbose := nqp::getenvhash<RAKUDO_LOG_PRECOMP>;

    submethod TWEAK(:$!name = 'lib', :$!lock = Lock.new) {
        CompUnit::RepositoryRegistry.register-name($!name, self);
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
    }

    method installed(--> Seq) {
        my $dist-dirs := $!prefix.IO.dir.grep(*.d).grep(*.child('META6.json').e);
        return $dist-dirs.map: { self!read-dist($_.basename) }
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
                my $meta = $_.meta;
                $meta<source> ||= $.prefix.add($_.id).add($meta<files>{$file}).IO.absolute;
                $meta;
            }

            return $absolutified-metas.grep(*.<source>.IO.e);
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
                my $meta = $_.meta;
                $meta<source> ||= $.prefix.add($_.id).add($meta<files>{$file}).IO.absolute;
                $meta;
            }

            return $absolutified-metas.grep(*.<source>.IO.e);
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
        return Empty unless $spec.from eq 'Perl6' || $spec.from eq 'Raku';

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

    method loaded(--> Iterable:D)  { %!loaded.values }
    method prefix(--> IO::Path:D)  { $!prefix.IO }
    method name(--> Str:D)         { $!name }
    method short-id(--> Str:D)     { 'lib' }
    method id(--> Str:D)           { $!id //= self.installed.map(*.id).sort.reduce({ nqp::sha1($^a ~ $^b) }) }
    method path-spec(--> Str:D)    { "CompUnit::Repository::Lib#name({$!name // 'lol'})#{self.prefix.absolute}" }
    method can-install(--> Bool:D) { $.prefix.w || ?(!$.prefix.e && try { $.prefix.mkdir } && $.prefix.e) }

    method !content-address($distribution, $name-path) { nqp::sha1($name-path ~ $distribution.id) }
    method !read-dist($dist-id) { Distribution::Lib.new( $!prefix.child($dist-id) ) }

    method need(
        CompUnit::DependencySpecification  $spec,
        CompUnit::PrecompilationRepository $precomp        = self.precomp-repository(),
        CompUnit::PrecompilationStore     :@precomp-stores = self!precomp-stores(),
    --> CompUnit:D) {

        return %!loaded{~$spec} if %!loaded{~$spec}:exists;

        with self!matching-dist($spec) {
            my $id = self!content-address($_, $spec.short-name);
            return %!loaded{$id} if %!loaded{$id}:exists;

            my $bytes  = Blob.new( $_.content($_.meta<provides>{$spec.short-name}).open(:bin).slurp(:bin, :close) );
            my $handle = CompUnit::Loader.load-source( $bytes );

            my $*RESOURCES = Distribution::Resources.new(:repo(self), :dist-id($_.id));
            my $compunit   = CompUnit.new(
                handle       => $handle,
                short-name   => $spec.short-name,
                version      => Version.new($_.meta<ver> // 0),
                auth         => ($_.meta<auth> // Str),
                repo         => self,
                repo-id      => $id,
                precompiled  => False,
                distribution => $_,
            );

            return %!loaded{~$spec} //= $compunit;
        }

        return self.next-repo.need($spec, $precomp, :@precomp-stores) if self.next-repo;
        X::CompUnit::UnsatisfiedDependency.new(:specification($spec)).throw;
    }

    method resolve(CompUnit::DependencySpecification $spec --> CompUnit:D) {
        with self!matching-dist($spec) {
            return CompUnit.new(
                :handle(CompUnit::Handle),
                :short-name($spec.short-name),
                :version(Version.new($_.meta<ver> // 0)),
                :auth($_.meta<auth> // Str),
                :repo(self),
                :repo-id(self!content-address($_, $spec.short-name)),
                :distribution($_),
            );
        }

        return self.next-repo.resolve($spec) if self.next-repo;
        Nil
    }


    method resource($dist-id, $key --> IO::Path) {
        self.prefix.child($dist-id).child("$key");
    }

    method uninstall(Distribution $distribution) {
        my $dist      = CompUnit::Repository::Distribution.new($distribution);
        my $dist-dir  = self.prefix.child($dist.id);

        my &unlink-if-exists := -> $path {
                $path.IO.d ?? (try { rmdir($path)  }) 
            !!  $path.IO.f ?? (try { unlink($path) })
            !! False
        }

        my &recursively-delete-empty-dirs := -> @_ {
            my @dirs = @_.grep(*.IO.d).map(*.&dir).map(*.Slip);
            &?BLOCK(@dirs) if +@dirs;
            unlink-if-exists( $_ ) for @dirs;
        }

        # special directory files
        for $dist.meta<files>.hash.kv -> $name-path, $file {
            # wrappers are located in "repos $bin-dir" (not dist repo)
            if $name-path.starts-with('bin/') && self.files($name-path).elems {
                unlink-if-exists( self.prefix.child("$name-path$_") ) for '', '-m', '-j';
                recursively-delete-empty-dirs([ self.prefix.child('bin') ]);
                unlink-if-exists( self.prefix.child('bin/') );
            }

            # distribution's bin/ and resources/
            unlink-if-exists( $dist-dir.child($name-path.IO.parent).child($file.IO.basename) );
        }

        # module/lib files
        for $dist.meta<provides>.hash.values.map(*.&parse-value) -> $name-path {
            unlink-if-exists( $dist-dir.child($name-path) );
        }

        # meta
        unlink-if-exists( $dist-dir.child("META6.json") );

        # delete remaining empty directories recursively
        recursively-delete-empty-dirs([$dist-dir]);
        unlink-if-exists( $dist-dir );
    }

    method install(Distribution $distribution, Bool :$force, Bool :$precompile = True) {
        my $dist = CompUnit::Repository::Distribution.new($distribution);
        fail "$dist already installed" if not $force and $dist.id ~~ self.installed.map(*.id).any;

        $!lock.protect: {
            my @*MODULES;
            my $dist-dir = self.prefix.child($dist.id) andthen *.mkdir;
            my $is-win   = Rakudo::Internals.IS-WIN;

            my $implicit-files := $dist.meta<provides>.values;
            my $explicit-files := $dist.meta<files>;
            my $all-files      := unique map { $_ ~~ Str ?? $_ !! $_.keys[0] },
                grep *.defined, $implicit-files.Slip, $explicit-files.Slip;

            for @$all-files -> $name-path {
                state %path2name = $dist.meta<provides>.antipairs;
                state @provides  = $dist.meta<provides>.values;

                given $name-path {
                    my $handle := $dist.content($name-path);
                    my $destination = $dist-dir.child($name-path) andthen *.parent.mkdir;

                    when /^@provides$/ {
                        my $name = %path2name{$name-path};
                        note("Installing {$name} for {$dist.meta<name>}") if $verbose and $name ne $dist.meta<name>;
                        $destination.spurt( $handle.open(:bin).slurp(:close) );
                    }

                    when /^bin\// {
                        my $name        = $name-path.subst(/^bin\//, '');
                        my $withoutext  = $name-path.subst(/\.[exe|bat]$/, '');

                        for '', '-j', '-m' -> $be {
                            mkdir $.prefix.child("$withoutext$be").IO.parent;
                            $.prefix.child("$withoutext$be").IO.spurt:
                                $raku_wrapper.subst('#name#', $name, :g).subst('#raku#', "raku$be");
                            if $is-win {
                                $.prefix.child("$withoutext$be.bat").IO.spurt:
                                    $windows_wrapper.subst('#raku#', "raku$be", :g);
                            }
                            else {
                                $.prefix.child("$withoutext$be").IO.chmod(0o755);
                            }
                        }

                        $destination.spurt( $handle.open(:bin).slurp(:close) );
                    }

                    when /^resources\/$<subdir>=(.*)/ {
                        my $subdir = $<subdir>; # maybe do something with libraries
                        $destination.spurt( $handle.open(:bin).slurp(:close) );
                    }
                }
            }

            spurt( $dist-dir.child('META6.json').absolute, Rakudo::Internals::JSON.to-json($dist.meta.hash) );

            # reset cached id so it's generated again on next access.
            # identity changes with every installation of a dist.
            $!id = Any;
            self!precompile-distribution-by-id($dist.id) if ?$precompile;
            return $dist;
        }
    }

    ### Precomp stuff beyond this point

   method !precompile-distribution-by-id($dist-id --> Bool:D) {
        my $dist         = self!read-dist($dist-id);
        my $precomp-repo = self.precomp-repository;

        $!lock.protect: {
            for $dist.meta<provides>.hash.kv -> $name, $name-path {
                state $compiler-id = CompUnit::PrecompilationId.new($*RAKU.compiler.id);
                my $precomp-id     = CompUnit::PrecompilationId.new(self!content-address($dist, $name-path));
                $precomp-repo.store.delete($compiler-id, $precomp-id);
            }

            {
                ENTER my $head = $*REPO;
                ENTER PROCESS::<$REPO> := self; # Precomp files should only depend on downstream repos
                LEAVE PROCESS::<$REPO> := $head;

                my $*RESOURCES = Distribution::Resources.new(:repo(self), :$dist-id);
                for $dist.meta<provides>.hash.kv -> $name, $name-path {
                    my $precomp-id  = CompUnit::PrecompilationId.new(self!content-address($dist, $name-path));
                    my $source-file = self.prefix.child($dist-id).child($name-path);

                    state %done;
                    if %done{$precomp-id}++ {
                        note "(Already did $precomp-id)" if $verbose;
                        next;
                    }

                    note("Precompiling $precomp-id ($name)") if $verbose;
                    $precomp-repo.precompile($source-file, $precomp-id, :source-name("$source-file ($name)"));
                }
            }
        }

        return True;
    }

    method !precomp-stores() {
        $!precomp-stores //= Array[CompUnit::PrecompilationStore].new(
            self.repo-chain.map(*.precomp-store).grep(*.defined)
        )
    }

    method precomp-store(--> CompUnit::PrecompilationStore) {
        $!precomp-store //= CompUnit::PrecompilationStore::File.new(
            :prefix(self.prefix.child('.precomp')),
        )
    }

    method precomp-repository(--> CompUnit::PrecompilationRepository) {
        $!precomp := CompUnit::PrecompilationRepository::Default.new(
            :store(self.precomp-store),
        ) unless $!precomp;
        $!precomp
    }
}
