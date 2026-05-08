package Git::Smart::Folder;

use strict;
use warnings;

use File::Spec;

sub usage_text {
    return <<'USAGE';
Usage:
  git.smart.folder update [SMART_FOLDER_BRANCH]

Examples:
  dashboard git.smart.folder update STACK-11095
  dashboard git.smart.folder update

Rules:
  - Run this inside a Git work tree.
  - If you are already on the smart folder branch, the branch name argument is optional.
  - If you are detached or on a child branch such as STACK-11095-2, supply the umbrella name explicitly.
  - The command fetches first, recreates the smart folder branch from origin/master,
    replays child branches in numeric order, refreshes local SM-* tags, and never pushes.
USAGE
}

sub main {
    my (@argv) = @_;
    my $subcommand = shift @argv;
    $subcommand = q{} if !defined $subcommand;

    if ( $subcommand eq q{} || $subcommand eq 'help' || $subcommand eq '-h' || $subcommand eq '--help' ) {
        print usage_text();
        return 0;
    }

    _die_msg("Unknown subcommand '$subcommand'. Run: dashboard git.smart.folder --help")
        if $subcommand ne 'update';

    my $smart_branch = resolve_smart_folder_name( $argv[0] );
    _require_git_work_tree();
    _handle_incomplete_cherry_pick($smart_branch);
    _require_clean_work_tree();

    _bootstrap_git_ssh();
    _run_checked( 'git', 'fetch', '--all', '--prune' );

    my $child_refs = discover_child_refs($smart_branch);
    rebuild_smart_folder( $smart_branch, $child_refs );

    print "Rebuilt ${smart_branch} on top of origin/master.\n";
    print "No push was performed.\n";
    return 0;
}

sub resolve_smart_folder_name {
    my ($explicit_name) = @_;
    return $explicit_name if defined $explicit_name && length $explicit_name;

    my ( $rc, $current_branch ) = _capture_first_line( 'git', 'symbolic-ref', '--quiet', '--short', 'HEAD' );

    _die_msg('No smart folder branch name supplied and HEAD is detached. Run: dashboard git.smart.folder update <branch-name>')
        if $rc != 0 || $current_branch eq q{};

    _die_msg("Current branch '$current_branch' looks like a child branch. Run: dashboard git.smart.folder update <smart-folder-branch>")
        if $current_branch =~ /\A.+-\d+-\d+\z/;

    _die_msg("Current branch '$current_branch' is not treated as a smart folder branch. Run: dashboard git.smart.folder update <branch-name>")
        if $current_branch eq 'master' || $current_branch eq 'main';

    return $current_branch;
}

sub discover_child_refs {
    my ($smart_branch) = @_;
    my %child_refs;

    my ( $rc, $refs ) = _capture_lines(
        'git',
        'for-each-ref',
        '--format=%(refname:short)',
        "refs/heads/${smart_branch}-*",
        "refs/remotes/origin/${smart_branch}-*",
    );
    _die_msg('Unable to discover child branches.') if $rc != 0;

    for my $ref (@{$refs}) {
        next if !defined $ref || $ref eq q{};

        my $branch_name = $ref;
        $branch_name =~ s{\Aorigin/}{};
        next if $branch_name !~ /^\Q$smart_branch\E-(\d+)\z/;

        my $number = $1;
        if ( $ref =~ /\Aorigin\// ) {
            $child_refs{$number} = $ref if !exists $child_refs{$number};
            next;
        }

        $child_refs{$number} = $ref;
    }

    _die_msg("No child branches found for prefix '${smart_branch}-'.") if !%child_refs;
    return \%child_refs;
}

sub rebuild_smart_folder {
    my ( $smart_branch, $child_refs ) = @_;
    my @child_numbers = sort { $a <=> $b } keys %{$child_refs};
    my $base_ref      = 'origin/master';

    print "Smart folder branch: ${smart_branch}\n";
    print "Child branches discovered:\n";
    for my $number (@child_numbers) {
        print "  ${smart_branch}-${number} -> $child_refs->{$number}\n";
    }

    _run_checked( 'git', 'checkout', '--detach', 'origin/master' );

    my $has_local_branch = _system_quiet( 'git', 'show-ref', '--verify', '--quiet', "refs/heads/${smart_branch}" ) == 0 ? 1 : 0;
    _run_checked( 'git', 'branch', '-D', $smart_branch ) if $has_local_branch;

    _run_checked( 'git', 'checkout', '-b', $smart_branch, 'origin/master' );

    for my $number (@child_numbers) {
        my $child_ref   = $child_refs->{$number};
        my $child_name  = $child_ref;
        my $tag_name;
        my $head_sha;
        my $applied_any;

        $child_name =~ s{\Aorigin/}{};
        $applied_any = cherry_pick_range( $base_ref, $child_ref );

        my ( $head_rc, $resolved_head ) = _capture_first_line( 'git', 'rev-parse', 'HEAD' );
        _die_msg('Unable to resolve HEAD after child branch processing.') if $head_rc != 0 || $resolved_head eq q{};
        $head_sha = $resolved_head;

        $tag_name = 'SM-' . $child_name;
        my $has_tag = _system_quiet( 'git', 'show-ref', '--verify', '--quiet', "refs/tags/${tag_name}" ) == 0 ? 1 : 0;
        _run_checked( 'git', 'tag', '-d', $tag_name ) if $has_tag;
        _run_checked( 'git', 'tag', $tag_name, $head_sha );
        print "Refreshed tag ${tag_name} at ${head_sha}\n";

        $base_ref = $child_ref;
    }

    return 1;
}

sub cherry_pick_range {
    my ( $base_ref, $child_ref ) = @_;

    my ( $rc, $commits ) = _capture_lines( 'git', 'rev-list', '--reverse', "${base_ref}..${child_ref}" );
    _die_msg("Unable to list commits for ${child_ref}.") if $rc != 0;

    if ( !@{$commits} ) {
        print "Skipping ${child_ref}; no commits beyond ${base_ref}.\n";
        return 0;
    }

    print 'Applying ' . $child_ref . ' (' . scalar( @{$commits} ) . " commit(s))\n";

    $rc = _system_quiet( 'git', 'cherry-pick', @{$commits} );
    return 1 if $rc == 0;

    while ( _cherry_pick_in_progress() ) {
        _resolve_add_add_conflicts();
        $rc = _system_quiet( 'git', 'cherry-pick', '--continue' );
        last if $rc == 0;
    }

    _die_msg("Cherry-pick did not complete for ${child_ref}.") if _cherry_pick_in_progress();
    return 1;
}

sub _require_git_work_tree {
    my ( $rc, $inside ) = _capture_first_line( 'git', 'rev-parse', '--is-inside-work-tree' );
    _die_msg('Run this command inside a Git work tree.') if $rc != 0 || $inside ne 'true';
    return 1;
}

sub _handle_incomplete_cherry_pick {
    my ($smart_branch) = @_;
    return 1 if !_cherry_pick_in_progress();

    my ( $rc, $current_branch ) = _capture_first_line( 'git', 'symbolic-ref', '--quiet', '--short', 'HEAD' );
    if ( $rc == 0 && $current_branch eq $smart_branch ) {
        print "Aborting in-progress cherry-pick on disposable smart folder branch ${smart_branch}.\n";
        _run_checked( 'git', 'cherry-pick', '--abort' );
        return 1;
    }

    _die_msg('An incomplete cherry-pick is already in progress outside the disposable smart folder branch. Resolve it before running git.smart.folder update.');
}

sub _require_clean_work_tree {
    _run_checked( 'git', 'update-index', '-q', '--refresh' );
    my ( $rc, $lines ) = _capture_lines( 'git', 'status', '--porcelain' );
    _die_msg('Unable to inspect working tree state.') if $rc != 0;
    _die_msg('Working tree is not clean. Commit, stash, or clean files before running git.smart.folder update.')
        if @{$lines};
    return 1;
}

sub _bootstrap_git_ssh {
    my $path = "$ENV{HOME}/.developer-dashboard/config/ssh-agent.env";
    return if !-f $path;

    open my $fh, '<', $path or return;
    while ( my $line = <$fh> ) {
        chomp $line;
        next if $line !~ /\A(SSH_AUTH_SOCK|SSH_AGENT_PID)=(.*)\z/;
        $ENV{$1} = $2;
    }
    close $fh;

    return 1;
}

sub _resolve_add_add_conflicts {
    my ( $rc, $conflicts ) = _capture_lines( 'git', 'diff', '--name-only', '--diff-filter=U' );
    _die_msg('Unable to inspect cherry-pick conflicts.') if $rc != 0;
    _die_msg('Cherry-pick stopped without a resolvable conflict list.') if !@{$conflicts};

    for my $file (@{$conflicts}) {
        my ( $status_rc, $status_line ) = _capture_first_line( 'git', 'status', '--porcelain', '--', $file );
        _die_msg("Unable to inspect conflict status for ${file}.") if $status_rc != 0;

        my $status = substr( $status_line || q{}, 0, 2 );
        _die_msg("Stopped on unsupported conflict type in ${file}. Resolve it manually, then run git cherry-pick --continue.")
            if $status ne 'AA';

        print "Resolving add/add conflict in ${file} by taking the later child branch version.\n";
        _run_checked( 'git', 'checkout', '--theirs', '--', $file );
        _run_checked( 'git', 'add', '--', $file );
    }

    return 1;
}

sub _cherry_pick_in_progress {
    my ($rc) = _capture_lines( 'git', 'rev-parse', '--verify', '--quiet', 'CHERRY_PICK_HEAD' );
    return $rc == 0 ? 1 : 0;
}

sub _run_checked {
    my (@cmd) = @_;
    my $rc = _system_quiet(@cmd);
    _die_msg( 'Command failed (' . $rc . '): ' . join( q{ }, @cmd ) ) if $rc != 0;
    return 1;
}

sub _system_quiet {
    my (@cmd) = @_;
    my $command = join q{ }, map { _shell_quote($_) } @cmd;
    my $devnull = File::Spec->devnull();
    my $prefix = q{};
    if ( @cmd && $cmd[0] eq 'git' ) {
        $prefix = "GIT_EDITOR=':' EDITOR=':' VISUAL=':' ";
    }
    system 'sh', '-c', $prefix . $command . ' >' . _shell_quote($devnull) . ' 2>' . _shell_quote($devnull);
    return $? >> 8;
}

sub _shell_quote {
    my ($value) = @_;
    $value =~ s/'/'\\''/g;
    return q{'} . $value . q{'};
}

sub _capture_lines {
    my (@cmd) = @_;
    my $command = join q{ }, map { _shell_quote($_) } @cmd;
    my $devnull = File::Spec->devnull();
    open my $fh, '-|', 'sh', '-c', $command . ' 2>' . _shell_quote($devnull)
        or _die_msg( 'Unable to run command: ' . join( q{ }, @cmd ) );
    my @lines = <$fh>;
    close $fh;
    my $rc = $? >> 8;
    chomp @lines;
    return ( $rc, \@lines );
}

sub _capture_first_line {
    my (@cmd) = @_;
    my ( $rc, $lines ) = _capture_lines(@cmd);
    my $line = @{$lines} ? $lines->[0] : q{};
    return ( $rc, $line );
}

sub _die_msg {
    my ($message) = @_;
    die $message . "\n";
}

1;
