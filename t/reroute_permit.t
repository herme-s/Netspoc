#!perl

use strict;
use warnings;
use Test::More;
use Test::Differences;
use lib 't';
use Test_Netspoc;

my ($title, $in, $out, $topo);

############################################################
$topo = <<'END';
network:n1 = { ip = 10.1.1.0/24; host:h1 = { ip = 10.1.1.10; } }
network:n2 = { ip = 10.1.2.0/24; }
network:n3 = { ip = 10.1.3.0/24; host:h3 = { ip = 10.1.3.10; } }

router:r1 = {
 managed;
 model = IOS;
 log:a = log-input;
 interface:n1 = { ip = 10.1.1.1; hardware = n1; }
 interface:n2 = { ip = 10.1.2.1; hardware = n2; }
}

router:asa2 = {
 managed;
 model = ASA;
 log:a = errors;
 log:b = debugging;
 log:c = disable;
 interface:n2 = { ip = 10.1.2.2; hardware = n2; }
 interface:n3 = { ip = 10.1.3.2; hardware = n3; }
}
END

############################################################
$title = 'Only use network';
############################################################

$in = <<'END';
group:g =
 interface:r1.n1,
 interface:r1.[auto],
 any:n1,
 any:[ip=10.0.0.0/8 & network:n1]
;
any:n1 = { link = network:n1; }
network:n1 = { ip = 10.1.1.0/24; host:h1 = { ip = 10.1.1.10; } }
router:r1 = {
 managed;
 model = ASA;
 interface:n1 = {
  ip = 10.1.1.1;
  hardware = n1;
  reroute_permit = host:h1, group:g;
 }
}
END

$out = <<'END';
Error: host:h1 not allowed in attribute 'reroute_permit' of interface:r1.n1
Error: interface:r1.n1 not allowed in attribute 'reroute_permit' of interface:r1.n1
Error: interface:r1.[auto] not allowed in attribute 'reroute_permit' of interface:r1.n1
Error: any:n1 not allowed in attribute 'reroute_permit' of interface:r1.n1
Error: any:[ip=10.0.0.0/8 & network:n1] not allowed in attribute 'reroute_permit' of interface:r1.n1
END

test_err($title, $in, $out);

############################################################
$title = 'Not at unmanaged';
############################################################

$in = <<'END';
network:n1 = { ip = 10.1.1.0/24; host:h1 = { ip = 10.1.1.10; } }
router:r1 = {
 interface:n1 = { ip = 10.1.1.1; reroute_permit = network:n1; }
}
END

$out = <<'END';
Warning: Ignoring attribute 'reroute_permit' at unmanaged interface:r1.n1
END

test_warn($title, $in, $out);

############################################################
$title = 'Check zone';
############################################################

$in = <<'END';
network:n1 = { ip = 10.1.1.0/24; }
router:r1 = {
 managed;
 model = ASA;
 interface:n1 = {
  ip = 10.1.1.1;
  hardware = n1;
  reroute_permit = network:n2;
 }
 interface:n2 = { ip = 10.1.2.1; hardware = n2; }
}
network:n2 = { ip = 10.1.2.0/24; }
END

$out = <<'END';
Error: Invalid reroute_permit for network:n2 at interface:r1.n1: different security zones
END

test_err($title, $in, $out);

############################################################
$title = 'Permit directly connected network';
############################################################

$in = <<'END';
network:n1 = { ip = 10.1.1.0/24; }
router:r1 = {
 managed;
 model = ASA;
 interface:n1 = {
  ip = 10.1.1.1;
  hardware = n1;
  reroute_permit = network:n1;
 }
 interface:n2 = { ip = 10.1.2.1; hardware = n2; }
}
network:n2 = { ip = 10.1.2.0/24; }
END

$out = <<'END';
--r1
! n1_in
access-list n1_in extended permit ip any4 10.1.1.0 255.255.255.0
access-list n1_in extended deny ip any4 any4
access-group n1_in in interface n1
END

test_run($title, $in, $out);

############################################################
$title = 'Forbidden with outgoing ACL';
############################################################

$in = <<'END';
network:n1 = { ip = 10.1.1.0/24; }
network:n2 = { ip = 10.1.2.0/24; }
router:u = {
 interface:n1;
 interface:n2 = { ip = 10.1.2.1; }
}
router:r1 = {
 managed;
 model = ASA;
 interface:n2 = {
  ip = 10.1.2.2;
  hardware = n2;
  reroute_permit = network:n2;
 }
 interface:n3 = { ip = 10.1.3.1; hardware = n3; no_in_acl; }
}
network:n3 = { ip = 10.1.3.0/24; }
END

$out = <<'END';
Error: Must not use attributes no_in_acl and reroute_permit together at router:r1
 Add incoming and outgoing ACL line in raw file instead.
END

test_err($title, $in, $out);

############################################################
$title = 'Forbidden at no_in_acl interface';
############################################################

$in = <<'END';
network:n1 = { ip = 10.1.1.0/24; }
router:r1 = {
 managed;
 model = ASA;
 interface:n1 = { ip = 10.1.1.1; hardware = n1; }
 interface:n2 = { ip = 10.1.2.1; hardware = n2; reroute_permit = network:n2;
 no_in_acl; }
}
network:n2 = { ip = 10.1.2.0/24; }
END

$out = <<'END';
Error: Useless use of attribute reroute_permit together with no_in_acl at interface:r1.n2
END

test_err($title, $in, $out);


############################################################
$title = 'Multiple networks from automatic group';
############################################################

$in = <<'END';
network:n1 = { ip = 10.1.1.0/24; }
network:n2 = { ip = 10.1.2.0/24; }
router:u = {
 interface:n1;
 interface:n2;
 interface:n3 = { ip = 10.1.3.1; }
}
network:n3 = { ip = 10.1.3.0/24; }
router:r1 = {
 managed;
 model = ASA;
 interface:n3 = {
  ip = 10.1.3.2;
  hardware = n3;
  reroute_permit = network:[any:[network:n1]];
 }
 interface:n4 = { ip = 10.1.4.1; hardware = n4; }
}
network:n4 = { ip = 10.1.4.0/24; }
END

$out = <<'END';
-- r1
! n3_in
object-group network g0
 network-object 10.1.1.0 255.255.255.0
 network-object 10.1.2.0 255.255.254.0
access-list n3_in extended permit ip any4 object-group g0
access-list n3_in extended deny ip any4 any4
access-group n3_in in interface n3
END

test_run($title, $in, $out);

############################################################
$title = 'Multiple networks from automatic group (Linux)';
############################################################

$in =~ s/ASA/Linux/;

$out = <<'END';
-- r1
:c1 -
-A c1 -j ACCEPT -d 10.1.2.0/23
-A c1 -j ACCEPT -d 10.1.1.0/24
--
:n3_self -
-A INPUT -j n3_self -i n3
:n3_n3 -
-A n3_n3 -g c1 -d 10.1.0.0/22
-A FORWARD -j n3_n3 -i n3 -o n3
END

test_run($title, $in, $out);

############################################################
done_testing;
