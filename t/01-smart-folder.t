use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use FindBin qw($Bin);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib File::Spec->catdir( $Bin, '..', 'lib' );

use Git::Smart::Folder ();

my $ROOT       = abs_path( File::Spec->catdir( $Bin, '..' ) );
my $CLI_PATH   = File::Spec->catfile( $ROOT, 'skills', 'smart', 'cli', 'folder' );
my $MODULE_LIB = File::Spec->catdir( $ROOT, 'lib' );

subtest 'help text is available' => sub {
    my $sandbox = tempdir( CLEANUP => 1 );
    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(--help)], $sandbox );
    is( $exit, 0, 'help exits cleanly' );
    is( $stderr, q{}, 'help does not print stderr' );
    like( $stdout, qr/git\.smart\.folder update/, 'usage text names the nested command' );
};

subtest 'unknown subcommand fails clearly' => sub {
    my $sandbox = tempdir( CLEANUP => 1 );
    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(nope)], $sandbox );
    is( $exit, 1, 'unknown subcommand exits nonzero' );
    like( $stderr, qr/Unknown subcommand 'nope'/, 'unknown subcommand error is clear' );
    is( $stdout, q{}, 'unknown subcommand does not print normal stdout' );
};

subtest 'non git directory fails clearly' => sub {
    my $sandbox = tempdir( CLEANUP => 1 );
    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(update STACK-11095)], $sandbox );
    is( $exit, 1, 'non git directory exits nonzero' );
    like( $stderr, qr/Run this command inside a Git work tree\./, 'non git error is clear' );
    is( $stdout, q{}, 'non git failure does not print success output' );
};

subtest 'explicit and implicit update flows plus tag movement' => sub {
    my $env = create_linear_stack_env();
    my $work = $env->{work};
    my $fake_home = create_fake_home_with_ssh_agent();

    my ( $stdout1, $stderr1, $exit1 ) = run_module_capture( [qw(update STACK-11095)], $work, { HOME => $fake_home } );
    is( $exit1, 0, 'explicit update succeeds' );
    is( $stderr1, q{}, 'explicit update does not print stderr' );
    like( $stdout1, qr/Smart folder branch: STACK-11095/, 'resolved branch is printed' );
    like( $stdout1, qr/STACK-11095-1 -> STACK-11095-1/, 'local child branch is listed' );
    like( $stdout1, qr/STACK-11095-2 -> STACK-11095-2/, 'local child override branch is listed' );
    like( $stdout1, qr/Skipping origin\/STACK-11095-3; no commits beyond STACK-11095-2\./, 'empty child ranges are skipped clearly' );
    like( $stdout1, qr/Refreshed tag SM-STACK-11095-3 at /, 'tag refresh is printed for skipped children too' );
    like( $stdout1, qr/No push was performed\./, 'no push message is printed' );

    my $current_branch = capture_stdout( [ 'git', 'branch', '--show-current' ], $work );
    chomp $current_branch;
    is( $current_branch, 'STACK-11095', 'update leaves the rebuilt smart folder branch checked out' );

    my $tree = capture_stdout( [ 'git', 'show', 'HEAD:stack.txt' ], $work );
    is( $tree, "one\nlocal-two\n", 'rebuilt branch content reflects ordered child replay and local override' );

    my $tag_two_first = capture_stdout( [ 'git', 'rev-parse', 'SM-STACK-11095-2' ], $work );
    chomp $tag_two_first;
    ok( $tag_two_first ne q{}, 'tag for second child exists after first run' );

    run_checked( [ 'git', 'checkout', 'STACK-11095-2' ], $work );
    overwrite_file(
        File::Spec->catfile( $work, 'stack.txt' ),
        "one\nlocal-two\nrerun-three\n",
    );
    run_checked( [ 'git', 'add', 'stack.txt' ], $work );
    run_checked( [ 'git', 'commit', '-m', 'Extend local child two' ], $work );
    run_checked( [ 'git', 'checkout', 'STACK-11095' ], $work );

    my ( $stdout2, $stderr2, $exit2 ) = run_module_capture( [qw(update)], $work, { HOME => $fake_home } );
    is( $exit2, 0, 'implicit update succeeds while on umbrella branch' );
    is( $stderr2, q{}, 'implicit update does not print stderr' );
    like( $stdout2, qr/Smart folder branch: STACK-11095/, 'implicit resolution uses the current umbrella branch' );

    my $updated_tree = capture_stdout( [ 'git', 'show', 'HEAD:stack.txt' ], $work );
    is( $updated_tree, "one\nlocal-two\nrerun-three\n", 'rerun rebuild uses the newer local child content' );

    my $tag_two_second = capture_stdout( [ 'git', 'rev-parse', 'SM-STACK-11095-2' ], $work );
    chomp $tag_two_second;
    isnt( $tag_two_second, $tag_two_first, 'marker tag moves on rerun' );
};

subtest 'nested cli wrapper dispatches successfully' => sub {
    my $env = create_linear_stack_env();
    my $work = $env->{work};

    my ( $stdout, $stderr, $exit ) = run_cli_capture( [qw(update STACK-11095)], $work );
    is( $exit, 0, 'cli wrapper exits cleanly' );
    like( $stdout, qr/No push was performed\./, 'cli wrapper prints the final no-push line' );
    is( $stderr, q{}, 'cli wrapper does not print stderr' );
};

subtest 'numbering gaps are preserved in numeric order' => sub {
    my $env = create_gap_env();
    my $work = $env->{work};

    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(update STACK-22000)], $work );
    is( $exit, 0, 'gapped stack update succeeds' );
    is( $stderr, q{}, 'gapped stack update does not print stderr' );
    like( $stdout, qr/STACK-22000-1 -> origin\/STACK-22000-1/, 'first child is listed' );
    like( $stdout, qr/STACK-22000-3 -> origin\/STACK-22000-3/, 'third child is listed' );
    like( $stdout, qr/STACK-22000-5 -> origin\/STACK-22000-5/, 'fifth child is listed' );

    my @subjects = split /\n/, capture_stdout( [ 'git', 'log', '--reverse', '--format=%s', 'origin/master..HEAD' ], $work );
    is_deeply(
        \@subjects,
        [ 'Child one', 'Child three', 'Child five' ],
        'gapped child branches are replayed in numeric order'
    );
};

subtest 'detached head requires an explicit umbrella branch' => sub {
    my $env = create_linear_stack_env();
    my $work = $env->{work};
    run_checked( [ 'git', 'checkout', '--detach', 'origin/master' ], $work );

    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(update)], $work );
    is( $exit, 1, 'detached head exits nonzero without explicit branch name' );
    like( $stderr, qr/HEAD is detached/, 'detached head error is clear' );
    is( $stdout, q{}, 'detached head failure does not print stdout' );
};

subtest 'child branch implicit resolution is rejected' => sub {
    my $env = create_linear_stack_env();
    my $work = $env->{work};
    run_checked( [ 'git', 'checkout', 'STACK-11095-2' ], $work );

    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(update)], $work );
    is( $exit, 1, 'child branch implicit update exits nonzero' );
    like( $stderr, qr/looks like a child branch/, 'child branch implicit error is clear' );
    is( $stdout, q{}, 'child branch implicit error does not print stdout' );
};

subtest 'master and main implicit resolution are rejected' => sub {
    my $master_env = create_linear_stack_env();
    my ( $stdout_m, $stderr_m, $exit_m ) = run_module_capture( [qw(update)], $master_env->{work} );
    is( $exit_m, 1, 'master implicit update exits nonzero' );
    like( $stderr_m, qr/not treated as a smart folder branch/, 'master implicit error is clear' );
    is( $stdout_m, q{}, 'master implicit error does not print stdout' );

    my $main_env = create_main_branch_env();
    my ( $stdout_n, $stderr_n, $exit_n ) = run_module_capture( [qw(update)], $main_env->{work} );
    is( $exit_n, 1, 'main implicit update exits nonzero' );
    like( $stderr_n, qr/not treated as a smart folder branch/, 'main implicit error is clear' );
    is( $stdout_n, q{}, 'main implicit error does not print stdout' );
};

subtest 'dirty working tree fails clearly' => sub {
    my $env = create_linear_stack_env();
    my $work = $env->{work};
    append_file( File::Spec->catfile( $work, 'README.tmp' ), "dirty\n" );

    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(update STACK-11095)], $work );
    is( $exit, 1, 'dirty working tree exits nonzero' );
    like( $stderr, qr/Working tree is not clean/, 'dirty tree error is clear' );
    is( $stdout, q{}, 'dirty tree failure does not print stdout' );
};

subtest 'missing child branches fail clearly' => sub {
    my $env = create_base_repo_env( branch_name => 'master' );
    my $work = $env->{work};

    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(update STACK-99999)], $work );
    is( $exit, 1, 'missing child branches exit nonzero' );
    like( $stderr, qr/No child branches found for prefix 'STACK-99999-'\./, 'missing child branch error is clear' );
    is( $stdout, q{}, 'missing child branches failure does not print stdout' );
};

subtest 'incomplete cherry pick state is rejected before rebuild' => sub {
    my $env = create_non_add_add_conflict_env();
    my $work = $env->{work};

    run_checked( [ 'git', 'checkout', 'STACK-33000' ], $work );
    my $first_commit = capture_stdout( [ 'git', 'rev-list', '--reverse', 'origin/master..origin/STACK-33000-1' ], $work );
    chomp $first_commit;
    run_checked( [ 'git', 'cherry-pick', $first_commit ], $work );
    my $second_commit = capture_stdout( [ 'git', 'rev-list', '--reverse', 'origin/STACK-33000-1..origin/STACK-33000-2' ], $work );
    chomp $second_commit;
    system_in_dir( [ 'git', 'cherry-pick', $second_commit ], $work );

    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(update STACK-33000)], $work );
    is( $exit, 1, 'incomplete cherry-pick exits nonzero' );
    like( $stderr, qr/incomplete cherry-pick is already in progress/, 'incomplete cherry-pick error is clear' );
    is( $stdout, q{}, 'incomplete cherry-pick failure does not print stdout' );
};

subtest 'add add conflicts are auto resolved using the later child version' => sub {
    my $env = create_add_add_conflict_env();
    my $work = $env->{work};

    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(update STACK-44000)], $work );
    is( $exit, 0, 'add/add conflict stack rebuild succeeds' );
    is( $stderr, q{}, 'add/add conflict stack rebuild does not print stderr' );
    like( $stdout, qr/Resolving add\/add conflict in conflict.txt by taking the later child branch version\./, 'add/add resolution is reported' );

    my $content = capture_stdout( [ 'git', 'show', 'HEAD:conflict.txt' ], $work );
    is( $content, "child-two\n", 'later child branch version wins add/add conflict resolution' );
};

subtest 'unsupported conflicts fail clearly' => sub {
    my $env = create_non_add_add_conflict_env();
    my $work = $env->{work};

    my ( $stdout, $stderr, $exit ) = run_module_capture( [qw(update STACK-33000)], $work );
    is( $exit, 1, 'unsupported conflict stack exits nonzero' );
    like( $stderr, qr/Stopped on unsupported conflict type in conflict.txt/, 'unsupported conflict error is clear' );
    like( $stdout, qr/Smart folder branch: STACK-33000/, 'failing run still prints the smart folder context' );
};

done_testing();

sub create_linear_stack_env {
    my $env = create_base_repo_env( branch_name => 'master' );
    my $seed = $env->{seed};
    my $work = $env->{work};

    run_checked( [ 'git', 'checkout', '-b', 'STACK-11095-1', 'master' ], $seed );
    overwrite_file( File::Spec->catfile( $seed, 'stack.txt' ), "one\n" );
    run_checked( [ 'git', 'add', 'stack.txt' ], $seed );
    run_checked( [ 'git', 'commit', '-m', 'Child one' ], $seed );
    run_checked( [ 'git', 'push', '-u', 'origin', 'STACK-11095-1' ], $seed );

    run_checked( [ 'git', 'checkout', '-b', 'STACK-11095-2', 'STACK-11095-1' ], $seed );
    overwrite_file( File::Spec->catfile( $seed, 'stack.txt' ), "one\nremote-two\n" );
    run_checked( [ 'git', 'add', 'stack.txt' ], $seed );
    run_checked( [ 'git', 'commit', '-m', 'Remote child two' ], $seed );
    run_checked( [ 'git', 'push', '-u', 'origin', 'STACK-11095-2' ], $seed );

    run_checked( [ 'git', 'checkout', '-b', 'STACK-11095-3', 'STACK-11095-2' ], $seed );
    run_checked( [ 'git', 'push', '-u', 'origin', 'STACK-11095-3' ], $seed );

    run_checked( [ 'git', 'checkout', 'master' ], $seed );
    run_checked( [ 'git', 'checkout', '-b', 'STACK-11095' ], $seed );
    run_checked( [ 'git', 'push', '-u', 'origin', 'STACK-11095' ], $seed );

    run_checked( [ 'git', '-C', $work, 'fetch', '--all', '--prune' ], $ROOT );
    run_checked( [ 'git', '-C', $work, 'checkout', '-b', 'STACK-11095', 'origin/STACK-11095' ], $ROOT );
    run_checked( [ 'git', '-C', $work, 'checkout', '-b', 'STACK-11095-1', 'origin/STACK-11095-1' ], $ROOT );
    run_checked( [ 'git', '-C', $work, 'checkout', '-b', 'STACK-11095-2', 'origin/STACK-11095-2' ], $ROOT );
    overwrite_file( File::Spec->catfile( $work, 'stack.txt' ), "one\nlocal-two\n" );
    run_checked( [ 'git', '-C', $work, 'add', 'stack.txt' ], $ROOT );
    run_checked( [ 'git', '-C', $work, 'commit', '-m', 'Local child two override' ], $ROOT );
    run_checked( [ 'git', '-C', $work, 'checkout', 'master' ], $ROOT );

    return $env;
}

sub create_gap_env {
    my $env = create_base_repo_env( branch_name => 'master' );
    my $seed = $env->{seed};
    my $work = $env->{work};

    create_branch_with_commit( $seed, 'master',         'STACK-22000-1', 'stack.txt', "one\n",              'Child one' );
    create_branch_with_commit( $seed, 'STACK-22000-1', 'STACK-22000-3', 'stack.txt', "one\nthree\n",       'Child three' );
    create_branch_with_commit( $seed, 'STACK-22000-3', 'STACK-22000-5', 'stack.txt', "one\nthree\nfive\n", 'Child five' );
    create_remote_branch( $seed, 'master', 'STACK-22000' );

    run_checked( [ 'git', '-C', $work, 'fetch', '--all', '--prune' ], $ROOT );
    run_checked( [ 'git', '-C', $work, 'checkout', '-b', 'STACK-22000', 'origin/STACK-22000' ], $ROOT );

    return $env;
}

sub create_main_branch_env {
    my $env = create_base_repo_env( branch_name => 'main' );
    my $seed = $env->{seed};
    my $work = $env->{work};

    create_remote_branch( $seed, 'main', 'STACK-12000' );
    create_branch_with_commit( $seed, 'main', 'STACK-12000-1', 'stack.txt', "one\n", 'Child one' );

    run_checked( [ 'git', '-C', $work, 'fetch', '--all', '--prune' ], $ROOT );
    run_checked( [ 'git', '-C', $work, 'checkout', 'main' ], $ROOT );

    return $env;
}

sub create_add_add_conflict_env {
    my $env = create_base_repo_env( branch_name => 'master' );
    my $seed = $env->{seed};
    my $work = $env->{work};

    create_branch_with_commit( $seed, 'master', 'STACK-44000-1', 'conflict.txt', "child-one\n", 'Child one adds conflict file' );
    create_branch_with_commit( $seed, 'master', 'STACK-44000-2', 'conflict.txt', "child-two\n", 'Child two adds conflict file' );
    create_remote_branch( $seed, 'master', 'STACK-44000' );

    run_checked( [ 'git', '-C', $work, 'fetch', '--all', '--prune' ], $ROOT );

    return $env;
}

sub create_non_add_add_conflict_env {
    my $env = create_base_repo_env( branch_name => 'master' );
    my $seed = $env->{seed};
    my $work = $env->{work};

    overwrite_file( File::Spec->catfile( $seed, 'conflict.txt' ), "base\n" );
    run_checked( [ 'git', 'add', 'conflict.txt' ], $seed );
    run_checked( [ 'git', 'commit', '-m', 'Add base conflict file' ], $seed );
    run_checked( [ 'git', 'push', 'origin', 'master' ], $seed );

    run_checked( [ 'git', 'checkout', '-b', 'STACK-33000-1', 'master' ], $seed );
    run_checked( [ 'git', 'rm', 'conflict.txt' ], $seed );
    run_checked( [ 'git', 'commit', '-m', 'Delete conflict file' ], $seed );
    run_checked( [ 'git', 'push', '-u', 'origin', 'STACK-33000-1' ], $seed );

    run_checked( [ 'git', 'checkout', '-b', 'STACK-33000-2', 'master' ], $seed );
    overwrite_file( File::Spec->catfile( $seed, 'conflict.txt' ), "child-two\n" );
    run_checked( [ 'git', 'add', 'conflict.txt' ], $seed );
    run_checked( [ 'git', 'commit', '-m', 'Modify conflict file' ], $seed );
    run_checked( [ 'git', 'push', '-u', 'origin', 'STACK-33000-2' ], $seed );

    create_remote_branch( $seed, 'master', 'STACK-33000' );

    run_checked( [ 'git', '-C', $work, 'fetch', '--all', '--prune' ], $ROOT );
    run_checked( [ 'git', '-C', $work, 'checkout', '-b', 'STACK-33000', 'origin/STACK-33000' ], $ROOT );
    return $env;
}

sub create_base_repo_env {
    my (%args) = @_;
    my $branch_name = $args{branch_name} || 'master';
    my $root = tempdir( CLEANUP => 1 );
    my $origin = File::Spec->catdir( $root, 'origin.git' );
    my $seed = File::Spec->catdir( $root, 'seed' );
    my $work = File::Spec->catdir( $root, 'work' );

    run_checked( [ 'git', 'init', '--bare', '--initial-branch', $branch_name, $origin ], $ROOT );
    run_checked( [ 'git', 'init', '--initial-branch', $branch_name, $seed ], $ROOT );
    configure_repo($seed);
    overwrite_file( File::Spec->catfile( $seed, 'README.md' ), "base\n" );
    run_checked( [ 'git', 'add', 'README.md' ], $seed );
    run_checked( [ 'git', 'commit', '-m', 'Initial base' ], $seed );
    run_checked( [ 'git', 'remote', 'add', 'origin', $origin ], $seed );
    run_checked( [ 'git', 'push', '-u', 'origin', $branch_name ], $seed );

    run_checked( [ 'git', 'clone', $origin, $work ], $ROOT );
    configure_repo($work);

    return {
        origin      => $origin,
        root        => $root,
        seed        => $seed,
        work        => $work,
        branch_name => $branch_name,
    };
}

sub create_branch_with_commit {
    my ( $repo, $base, $branch, $file, $content, $subject ) = @_;
    run_checked( [ 'git', 'checkout', '-b', $branch, $base ], $repo );
    overwrite_file( File::Spec->catfile( $repo, $file ), $content );
    run_checked( [ 'git', 'add', $file ], $repo );
    run_checked( [ 'git', 'commit', '-m', $subject ], $repo );
    run_checked( [ 'git', 'push', '-u', 'origin', $branch ], $repo );
}

sub create_remote_branch {
    my ( $repo, $base, $branch ) = @_;
    run_checked( [ 'git', 'checkout', '-b', $branch, $base ], $repo );
    run_checked( [ 'git', 'push', '-u', 'origin', $branch ], $repo );
}

sub configure_repo {
    my ($repo) = @_;
    run_checked( [ 'git', 'config', 'user.name', 'Test User' ],  $repo );
    run_checked( [ 'git', 'config', 'user.email', 'test@example.com' ], $repo );
}

sub run_cli_capture {
    my ( $args, $cwd ) = @_;
    my $cmd = join q{ },
        map { _shell_quote($_) }
        ( $^X, '-I', $MODULE_LIB, $CLI_PATH, @{$args} );

    my $stdout = tempdir( CLEANUP => 1 ) . '/stdout.txt';
    my $stderr = tempdir( CLEANUP => 1 ) . '/stderr.txt';
    my $rc = system_in_dir(
        [ 'bash', '-lc', "$cmd >" . _shell_quote($stdout) . " 2>" . _shell_quote($stderr) ],
        $cwd,
    );

    return ( slurp_file($stdout), slurp_file($stderr), $rc );
}

sub run_module_capture {
    my ( $args, $cwd, $env ) = @_;
    my $stdout = q{};
    my $stderr = q{};
    my $exit;
    my $orig = getcwd();

    local %ENV = %ENV;
    if ($env) {
        @ENV{ keys %{$env} } = values %{$env};
    }

    open my $stdout_fh, '>', \$stdout or die 'Unable to open scalar stdout';
    open my $stderr_fh, '>', \$stderr or die 'Unable to open scalar stderr';

    chdir $cwd or die "Unable to chdir to $cwd: $!";
    {
        local *STDOUT = $stdout_fh;
        local *STDERR = $stderr_fh;
        $exit = eval { Git::Smart::Folder::main( @{$args} ) };
        if ( my $error = $@ ) {
            print STDERR $error;
            $exit = 1;
        }
    }
    chdir $orig or die "Unable to restore cwd to $orig: $!";

    return ( $stdout, $stderr, $exit );
}

sub capture_stdout {
    my ( $cmd, $cwd ) = @_;
    return system_in_dir_capture( $cmd, $cwd );
}

sub system_in_dir_capture {
    my ( $cmd, $cwd ) = @_;
    my $stdout_file = tempdir( CLEANUP => 1 ) . '/stdout.txt';
    my $command = join q{ }, map { _shell_quote($_) } @{$cmd};
    my $wrapper = 'cd ' . _shell_quote($cwd) . ' && ' . $command . ' >' . _shell_quote($stdout_file);
    my $rc = system 'bash', '-lc', $wrapper;
    die "Command failed while capturing output: $command" if ( $rc >> 8 ) != 0;
    return slurp_file($stdout_file);
}

sub system_in_dir {
    my ( $cmd, $cwd ) = @_;
    my $command = join q{ }, map { _shell_quote($_) } @{$cmd};
    my $wrapper = 'cd ' . _shell_quote($cwd) . ' && ' . $command;
    system 'bash', '-lc', $wrapper;
    return $? >> 8;
}

sub run_checked {
    my ( $cmd, $cwd ) = @_;
    my $rc = system_in_dir( $cmd, $cwd );
    die 'Command failed (' . $rc . '): ' . join( q{ }, @{$cmd} ) if $rc != 0;
}

sub overwrite_file {
    my ( $path, $content ) = @_;
    my ( $volume, $dirs ) = File::Spec->splitpath($path);
    make_path( File::Spec->catpath( $volume, $dirs, q{} ) );
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} $content;
    close $fh;
}

sub append_file {
    my ( $path, $content ) = @_;
    open my $fh, '>>', $path or die "Unable to append $path: $!";
    print {$fh} $content;
    close $fh;
}

sub slurp_file {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

sub create_fake_home_with_ssh_agent {
    my $home = tempdir( CLEANUP => 1 );
    my $config_dir = File::Spec->catdir( $home, '.developer-dashboard', 'config' );
    make_path($config_dir);
    overwrite_file(
        File::Spec->catfile( $config_dir, 'ssh-agent.env' ),
        "SSH_AUTH_SOCK=/tmp/fake-agent.sock\nSSH_AGENT_PID=12345\nIGNORED_VALUE=skip-me\n",
    );
    return $home;
}

sub _shell_quote {
    my ($value) = @_;
    $value =~ s/'/'\\''/g;
    return q{'} . $value . q{'};
}
