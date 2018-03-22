package Netspoc::Compiler::Common;

=head1 NAME

Common code of Pass1 and Pass2

=head1 COPYRIGHT AND DISCLAIMER

(C) 2017 by Heinz Knutzen <heinz.knutzen@googlemail.com>

http://hknutzen.github.com/Netspoc

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

=cut

use strict;
use warnings;

use Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(
 *config *SHOW_DIAG
 fatal_err debug info diag_msg
 $start_time progress
 ip2bitstr bitstr2ip
 $zero_ip $max_ip @inverse_masks
 increment_ip
 mask2prefix prefix2mask match_ip
 init_mask_prefix_lookups
 init_zero_and_max_ip
 init_inverse_masks
 init_prefix_len
);

# Enable printing of diagnostic messages by
# - either declaring main::SHOW_DIAG
# - or setting environment variable SHOW_DIAG.
use constant SHOW_DIAG => exists &main::SHOW_DIAG || $ENV{SHOW_DIAG};

our $config;

# Print error message and aborts.
sub fatal_err {
    my (@args) = @_;
    print STDERR "Error: ", @args, "\n";
    die "Aborted\n";
}

# Print arguments to STDERR if in verbose mode.
sub debug {
    # uncoverable subroutine
    my (@args) = @_;			# uncoverable statement
    return if not $config->{verbose};	# uncoverable statement
    print STDERR @args, "\n";		# uncoverable statement
}

# Print arguments to STDERR if in verbose mode.
sub info {
    my (@args) = @_;
    return if not $config->{verbose};
    print STDERR @args, "\n";
}

# Print diagnostic message, regardless of quiet/verbose setting.
# Should be used guarded by constant SHOW_DIAG.
# If SHOW_DIAG isn't enabled, the whole line will be removed at
# compile time and won't have any performane impact.
# Use like this:
# diag_msg("Some message") if SHOW_DIAG;
sub diag_msg {
    my (@args) = @_;
    print STDERR "DIAG: ", @args, "\n";
}

our $start_time;

# Print arguments to STDERR if in verbose mode.
# Add time stamps to output if configured.
sub progress {
    my (@args) = @_;
    return if not $config->{verbose};
    # uncoverable branch true
    if ($config->{time_stamps}) {
        my $diff = time() - $start_time;	# uncoverable statement
        unshift @args, sprintf "%3ds ", $diff;	# uncoverable statement
    }
    info(@args);
}

sub ip2bitstr {
    my ($ip) = @_;
    if ($ip =~ /:/) {
        return NetAddr::IP::Util::ipv6_aton($ip);
    }
    else {
        my ($i1,$i2,$i3,$i4) = split '\.', $ip;

        # Create bit string with 32 bits.
        return pack 'C4', $i1, $i2, $i3, $i4;
    }
}

## no critic (RequireArgUnpacking)
sub bitstr2ip {
    if (length($_[0]) == 16) {
        return NetAddr::IP::Util::ipv6_ntoa($_[0]);
    }
    else {
        return sprintf "%vd", $_[0];
    }
}

## use critic

our $zero_ip;
our $max_ip;

sub init_zero_and_max_ip {
    if ($config->{ipv6}) {
        $zero_ip = NetAddr::IP::Util::ipv6_aton('0:0:0:0:0:0:0:0');
        $max_ip = NetAddr::IP::Util::ipv6_aton(
            'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff');
    }
    else {
        $zero_ip = pack('N', 0);
        $max_ip = pack('N', 0xffffffff);
    }
}

our $prefix_len;

sub init_prefix_len {
    $prefix_len = $config->{ipv6} ? 128 : 32;
}

# 255.255.255.255, 127.255.255.255, ..., 0.0.0.3, 0.0.0.1, 0.0.0.0
our @inverse_masks;

sub init_inverse_masks {
    @inverse_masks = map { ~ prefix2mask($_) } (0 .. $prefix_len);
}

sub increment_ip  {
    my ($bitstring) = @_;

    if (length($bitstring) == 16) {
        my ($s1, $s2, $s3, $s4) = unpack('N4', $bitstring);
        if ($s4 == 0xffffffff) {
            $s4 = 0;
            if ($s3 == 0xffffffff) {
                $s3 = 0;
                if ($s2 == 0xffffffff) {
                    $s2 = 0;
                    $s1++;
                }
                else {
                    $s2++;
                }
            }
            else {
                $s3++;
            }
        }
        else {
            $s4++;
        }
        pack 'N4', $s1, $s2, $s3, $s4;
    }

    else {
        pack('N', 1 + unpack('N', $bitstring));
    }
}

# Conversion from netmask to prefix and vice versa.
{

    # Initialize private variables of this block.
    my %mask2prefix;
    my %prefix2mask;

    # Build mask in 32/128bit bitstring format from 1/4 32bit numbers.
    # [0000,0000],[1000,0000],[1100,0000],[1110,0000],[1111,0000],[1111,1000],..
    sub init_mask_prefix_lookups {
        my $size_32 = $config->{ipv6} ? 4 : 1;
        my @words = (0x00000000) x $size_32;
        my $index = 0;
        my $prefix = 0;
        while ($index < $size_32) {
            my $bit = 0x80000000;	# Highest bit is set.
            while (1) {
                my $mask = pack 'N*', @words;
                $mask2prefix{$mask}   = $prefix;
                $prefix2mask{$prefix} = $mask;
                last if $bit == 0;
                $words[$index] |= $bit;
                $bit >>= 1;
                $prefix++;
            }
            $index++;
        }
    }

    # Convert a network mask to a prefix ranging from 0 to 32/128.
    sub mask2prefix {
        my $mask = shift;
        return $mask2prefix{$mask};
    }

    sub prefix2mask {
        my $prefix = shift;
        return $prefix2mask{$prefix};
    }
}

# Check if $ip1 is located inside network $ip/$mask.
sub match_ip {
    my ($ip1, $ip, $mask) = @_;
    return ($ip eq ($ip1 & $mask));
}

1;
