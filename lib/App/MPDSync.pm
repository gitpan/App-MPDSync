package App::MPDSync;

use strict;
use warnings;
use 5.010;

our $VERSION = '0.01';

use Getopt::Long;
use Net::MPD;
use Proc::Daemon;

sub new {
  my ($class, @options) = @_;

  my $self = bless {
    from    => '',
    to      => 'localhost',
    daemon  => 1,
    verbose => 0,
    source  => undef,
    @options,
  }, $class;
}

sub parse_options {
  my ($self, @args) = @_;

  local @ARGV = @args;

  Getopt::Long::Configure('bundling');
  Getopt::Long::GetOptions(
    'D|daemon!' => \$self->{daemon},
    'V|version' => \&show_version,
    'f|from=s'  => \$self->{from},
    't|to=s'    => \$self->{to},
    'h|help'    => \&show_help,
    'v|verbose' => \$self->{verbose},
  );
}

sub vprint {
  my ($self, @message) = @_;
  say @message if $self->{verbose};
}

sub show_help {
  print <<'HELP';
Usage: mpd-sync [options] --from source [--to dest]

Options:
  -f,--from     Source MPD instance (required)
  -t,--to       Destination MPD instance (default localhost)
  -v,--verbose  Be noisy
  --no-daemon   Do not fork to background
  -V,--version  Show version and exit
  -h,--help     Show this help and exit
HELP

  exit;
}

sub show_version {
  say "mpd-sync (App::MPDSync) version $VERSION";
  exit;
}

sub execute {
  my ($self) = @_;

  local @SIG{qw{ INT TERM HUP }} = sub {
    exit 0;
  };

  unless ($self->{from}) {
    say STDERR 'Source MPD not provided';
    show_help;
  }

  my $source = Net::MPD->connect($self->{from});

  if ($self->{daemon}) {
    $self->vprint('Forking to background');
    Proc::Daemon::Init;
  }

  {
    $self->vprint('Syncrhonizing initial playlist');

    my $dest = Net::MPD->connect($self->{to});
    $dest->stop;
    $dest->clear;
    $dest->add($_->{uri}) for $source->playlist_info;

    $source->update_status;
    $dest->play;
    $dest->seek($source->song, int $source->elapsed);
  }

  while (1) {
    $source->idle('playlist');

    $self->vprint('Source playlist changed');

    $source->update_status;
    my @playlist = $source->playlist_info;

    my $dest = Net::MPD->connect($self->{to});
    foreach my $item ($dest->playlist_info) {
      if (@playlist) {
        if ($item->{uri} eq $playlist[0]{uri}) {
          shift @playlist;
        } else {
          $self->vprint("Removing $item->{uri} from destination playlist");
          $dest->delete_id($item->{Id});
        }
      } else {
        $self->vprint('Out of entries from source!');
      }
    }

    foreach (@playlist) {
      $self->vprint("Adding $_->{uri} to destination");
      $dest->add($_->{uri});
    }
  }
}

1;
__END__

=encoding utf-8

=head1 NAME

App::MPDSync - Synchronize MPD with another instance

=head1 SYNOPSIS

  > mpdsync --from otherhost --to localhost

=head1 DESCRIPTION

C<App::MPDSync> will keep an instance of C<MPD> synced with another instance.
This can be useful for having failover for an online radio station.

=head1 AUTHOR

Alan Berndt E<lt>alan@eatabrick.orgE<gt>

=head1 COPYRIGHT

Copyright 2014 Alan Berndt

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Net::MPD>

=cut
