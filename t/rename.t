#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Differences;
use IPC::Run3;
use File::Temp qw(tempfile);

# Disable locale, so we get non translated error message.
delete $ENV{LANG} ;

sub run {
    my ($input, $args) = @_;
    my ($in_fh, $filename) = tempfile(UNLINK => 1);
    print $in_fh $input;
    close $in_fh;
    my $perl_opt = $ENV{HARNESS_PERL_SWITCHES} || '';
    my $cmd = "$^X $perl_opt -I lib bin/rename-netspoc -q $filename $args";
    my $stderr;
    run3($cmd, \undef, \undef, \$stderr);
    my $status = $? >> 8;
    $stderr ||= '';
    $stderr =~ s/\Q$filename\E/INPUT/g;
    open(my $fh, '<', $filename) or die("Can't open $filename: $!\n");
    local $/ = undef;
    my $output = <$fh>;
    close($fh);
    return($status, $output, $stderr);
}

sub test_run {
    my ($title, $input, $args, $expected) = @_;
    my ($status, $output, $stderr) = run($input, $args);
    if ($status != 0) {
        diag("Unexpected failure:\n$stderr");
        fail($title);
    }
    eq_or_diff("$stderr$output", $expected, $title);
}

sub test_err {
    my ($title, $input, $args, $expected) = @_;
    my ($status, $output, $stderr) = run($input, $args);
    if ($status == 0) {
        diag("Unexpected success\n");
        fail($title);
    }
    $stderr =~ s/Aborted\n$//;
    eq_or_diff($stderr, $expected, $title);
}

my ($title, $in, $out);

############################################################
$title = 'Unknown type in substitution';
############################################################

$out = <<'END';
Error: Unknown type foo
END

test_err($title, '', 'foo:Test foo:Toast', $out);

############################################################
$title = 'Missing type in substitution';
############################################################

$out = <<'END';
Error: Missing type in 'Test'
END

test_err($title, '', 'Test Toast', $out);

############################################################
$title = 'Missing replace string';
############################################################

$out = <<'END';
Error: Missing replace string for 'host:z'
END

test_err($title, '', 'host:x host:y host:z', $out);

############################################################
$title = 'Types must be indentical';
############################################################

$in = '';

$out = <<'END';
Error: Types must be identical in
 - host:x
 - network:y
END

test_err($title, '', 'host:x network:y ', $out);

############################################################
$title = 'Rename network';
############################################################

$in = <<'END';
network:Test =  { ip = 10.9.1.0/24; }
group:G = interface:r.Test, # comment
    host:id:h@dom.top.Test,
    network:Test,
    ;
END

$out = <<'END';
network:Toast =  { ip = 10.9.1.0/24; }
group:G = interface:r.Toast, # comment
    host:id:h@dom.top.Toast,
    network:Toast,
    ;
END

test_run($title, $in, 'network:Test network:Toast', $out);

############################################################
$title = 'Rename verbosely';
############################################################

$out = <<'END' . $out;
4 changes in INPUT
END

test_run($title, $in, '--noquiet network:Test network:Toast', $out);

############################################################
$title = 'Rename bridged network';
############################################################

$in = <<'END';
network:Test/a = { ip = 10.9.1.0/24; }
network:Test/b = { ip = 10.9.1.0/24; }
group:G = interface:r.Test,
    network:Test/a,
    network:Test/b,
    interface:r.Test/b,
    ;
END

$out = <<'END';
network:Toast/a = { ip = 10.9.1.0/24; }
network:Toast/b = { ip = 10.9.1.0/24; }
group:G = interface:r.Toast,
    network:Toast/a,
    network:Toast/b,
    interface:r.Toast/b,
    ;
END

test_run($title, $in, 'network:Test network:Toast', $out);

############################################################
$title = 'Rename ID host';
############################################################

$in = <<'END';
group:G =
    host:id:h@dom.top.Test,
    host:id:h@dom.top.top,
    host:id:dom.top.Test,
    ;
END

$out = <<'END';
group:G =
    host:id:xx@yy.zz.Test,
    host:id:xx@yy.zz.top,
    host:id:a.b.c.Test,
    ;
END

test_run($title, $in,
         'host:id:h@dom.top host:id:xx@yy.zz host:id:dom.top host:id:a.b.c',
         $out);

############################################################
$title = 'Rename both, ID host and network';
############################################################

$in = <<'END';
group:G =
    host:id:h@dom.top.Test,
    host:id:h@dom.top.top,
    ;
END

$out = <<'END';
group:G =
    host:id:xx@yy.zz.Toast,
    host:id:xx@yy.zz.top,
    ;
END

test_run($title, $in,
         'host:id:h@dom.top host:id:xx@yy.zz network:Test network:Toast',
         $out);

###################################################
$title = 'Rename network to name with leading digit';
############################################################

$in = <<'END';
network:Test =  { ip = 10.9.1.0/24; }
group:G = interface:r.Test, # comment
    host:id:h@dom.top.Test,
    network:Test,
    ;
END

$out = <<'END';
network:1_2_3_0_Test =  { ip = 10.9.1.0/24; }
group:G = interface:r.1_2_3_0_Test, # comment
    host:id:h@dom.top.1_2_3_0_Test,
    network:1_2_3_0_Test,
    ;
END

test_run($title, $in, 'network:Test network:1_2_3_0_Test', $out);

############################################################
$title = 'Rename router then network';
############################################################

$in = <<'END';
router:R = { interface:NN = { ip = 10.9.1.1; } }
network:NN
interface:R.NN;
END

$out = <<'END';
router:RR = { interface:N = { ip = 10.9.1.1; } }
network:N
interface:RR.N;
END

test_run($title, $in, 'router:R router:RR network:NN network:N', $out);
$title = 'Rename network then router';
test_run($title, $in, 'network:NN network:N router:R router:RR', $out);

############################################################
$title = 'Rename VRF router';
############################################################

$in = <<'END';
router:R = { interface:n = { ip = 10.9.1.1; } }
router:R@vrf = { interface:n = { ip = 10.9.1.2; } }
group:G =
interface:R.n;
interface:R@vrf.n;
END

$out = <<'END';
router:RR = { interface:n = { ip = 10.9.1.1; } }
router:r@vrf = { interface:n = { ip = 10.9.1.2; } }
group:G =
interface:RR.n;
interface:r@vrf.n;
END

test_run($title, $in, 'router:R router:RR router:R@vrf router:r@vrf', $out);

############################################################
$title = 'Rename nat';
############################################################

$in = <<'END';
network:N = { ip = 1.2.3.0/24; nat:NAT-1 = {ip = 7.8.9.0; } }
bind_nat = NAT-1;
bind_nat = x, # comment
    y,NAT-1, z;
bind_nat =NAT-1#comment
    ;
bind_nat
= NAT-1;
END

$out = <<'END';
network:N = { ip = 1.2.3.0/24; nat:NAT-2 = {ip = 7.8.9.0; } }
bind_nat = NAT-2;
bind_nat = x, # comment
    y,NAT-2, z;
bind_nat =NAT-2#comment
    ;
bind_nat
= NAT-2;
END

test_run($title, $in, 'nat:NAT-1 nat:NAT-2', $out);

############################################################
$title = 'Rename loopback interface';
############################################################

$in = <<'END';
router:r1 = { interface:Loopback_4 = { ip = 10.9.1.1; loopback; } }
router:r2 = { interface:Loopback_4 = { ip = 10.9.1.2; loopback; } }
group:G = interface:r1.Loopback_4,
          interface:r2.Loopback_4,
    ;
END

$out = <<'END';
router:r1 = { interface:Loopback = { ip = 10.9.1.1; loopback; } }
router:r2 = { interface:Loopback = { ip = 10.9.1.2; loopback; } }
group:G = interface:r1.Loopback,
          interface:r2.Loopback,
    ;
END

test_run($title, $in, 'network:Loopback_4 network:Loopback', $out);

############################################################
$title = 'Rename umlauts';
############################################################

$in = <<'END';
owner:Maaß
owner:Wittmüß
owner = Maaß, Wittmuess
END

$out = <<'END';
owner:Maass
owner:Wittmüß
owner = Maass, Wittmüß
END

test_run($title, $in, 'owner:Maaß owner:Maass owner:Wittmuess owner:Wittmüß',
	 $out);

############################################################
$title = 'Read substitutions from file';
############################################################

my $subst = <<'END';
host:abc host:a1
owner:foo owner:büro
nat:tick nat:t1
nat:ticks nat:t2
nat:ick nat:_
network:net network:xxxx
END
my ($in_fh, $filename) = tempfile(UNLINK => 1);
print $in_fh $subst;
close $in_fh;

$in = <<'END';;
nat:ticks nat:ick
nat:tick
interface:net = { bind_nat = ick,
 ticks, tick;}
network:net = { owner = foo;
 host:abc;
}
END

$out = <<'END';;
nat:t2 nat:_
nat:t1
interface:xxxx = { bind_nat = _,
 t2, t1;}
network:xxxx = { owner = büro;
 host:a1;
}
END

test_run($title, $in, "-f $filename", $out);

############################################################
$title = 'Unknown file for substitutions';
############################################################

$out = <<'END';
Error: Can't open missing.file: No such file or directory
END

test_err($title, '', "-f missing.file", $out);

############################################################
done_testing;
