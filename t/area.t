#!perl

use strict;
use warnings;
use Test::More;
use Test::Differences;
use lib 't';
use Test_Netspoc;
use Test_Group;

my ($title, $in, $out, $topo);

############################################################
$topo = <<'END';
network:n1 = { ip = 10.1.1.0/24; host:h1 = { ip = 10.1.1.10; } }
network:n2 = { ip = 10.1.2.0/24; }
network:n3 = { ip = 10.1.3.0/24; host:h3 = { ip = 10.1.3.10; } }

router:asa1 = {
 managed;
 model = ASA;
 interface:n1 = { ip = 10.1.1.1; hardware = vlan1; }
 interface:n2 = { ip = 10.1.2.1; hardware = vlan2; }
}

router:asa2 = {
 managed;
 model = ASA;
 interface:n2 = { ip = 10.1.2.2; hardware = vlan2; }
 interface:n3 = { ip = 10.1.3.2; hardware = vlan3; }
}
END

############################################################
$title = 'Must not define anchor together with border';
############################################################

$in = $topo . <<'END';
area:a = {
 anchor = network:n1;
 border = interface:asa2.n2;
 inclusive_border = interface:asa2.n3;
}
END

$out = <<'END';
Error: Attribute 'anchor' must not be defined together with 'border' or 'inclusive_border' for area:a
END

test_err($title, $in, $out);

############################################################
$title = 'Must define either anchor or  border';
############################################################

$in = $topo . <<'END';
area:a = {}
END

$out = <<'END';
Error: At least one of attributes 'border', 'inclusive_border' or 'anchor' must be defined for area:a
END

test_err($title, $in, $out);

############################################################
$title = 'Only interface as border';
############################################################

$in = $topo . <<'END';
area:a = { inclusive_border = network:n1; }
END

$out = <<'END';
Error: Must only use interface names in 'inclusive_border' at line 18 of STDIN
END

test_err($title, $in, $out);

############################################################
$title = 'Unmanaged interface can\'t be border';
############################################################

$in = <<'END';
network:n1 = { ip = 10.1.1.0/24; }
router:r1 = { interface:n1; }
area:a = { border = interface:r1.n1; }
END

$out = <<'END';
Error: Referencing unmanaged interface:r1.n1 from area:a
Warning: area:a is empty
END

test_err($title, $in, $out);

############################################################
$title = 'Policy distribution point from nested areas';
############################################################

$in = $topo . <<'END';
# a3 < a2 < all, a1 < all
area:all = {
 anchor = network:n1;
 router_attributes = { policy_distribution_point = host:h1; }
}
area:a1 = { border = interface:asa1.n1; }
area:a2 = {
 border = interface:asa1.n2;
 router_attributes = { policy_distribution_point = host:h3; }
}
area:a3 = { border = interface:asa2.n3; }

service:pdp1 = {
 user = interface:[managed & area:all].[auto];
 permit src = host:h1; dst = user; prt = tcp 22;
}
service:pdp3 = {
 user = interface:[managed & area:a2].[auto];
 permit src = host:h3; dst = user; prt = tcp 22;
}
END

$out = <<'END';
--asa1
! [ IP = 10.1.1.1 ]
--asa2
! [ IP = 10.1.3.2 ]
END

test_run($title, $in, $out, '-check_policy_distribution_point=warn');

############################################################
$title = 'Missing policy distribution point';
############################################################

$in = $topo . <<'END';
area:all = {
 anchor = network:n1;
}
area:a2 = {
 border = interface:asa1.n2;
 router_attributes = { policy_distribution_point = host:h3; }
}

service:pdp1 = {
 user = interface:[managed & area:all].[auto];
 permit src = host:h1; dst = user; prt = tcp 22;
}
service:pdp3 = {
 user = interface:[managed & area:a2].[auto];
 permit src = host:h3; dst = user; prt = tcp 22;
}
END

$out = <<'END';
Warning: Missing policy_distribution_point for router:asa1
END

test_warn($title, $in, $out, '-check_policy_distribution_point=warn');

############################################################
$title = 'Overlapping areas';
############################################################

$in = $topo . <<'END';
network:n4 = { ip = 10.1.4.0/24; }
router:asa3 = {
 managed;
 model = ASA;
 interface:n2 = { ip = 10.1.2.3; hardware = vlan2; }
 interface:n4 = { ip = 10.1.4.1; hardware = vlan4; }
}
area:a2 = { border = interface:asa1.n2; }
area:a2x = { border = interface:asa2.n2; }
END

$out = <<'END';
Error: Overlapping area:a2 and area:a2x
END

test_err($title, $in, $out);

############################################################
$title = 'Duplicate areas';
############################################################

$in = $topo . <<'END';
area:a2 = { border = interface:asa1.n2; }
area:a2x = { border = interface:asa1.n2; }
END

$out = <<'END';
Error: Duplicate area:a2 and area:a2x
END

test_err($title, $in, $out);

############################################################
$title = 'Area with auto_border';
############################################################

$in = $topo . <<'END';
network:n4 = { ip = 10.1.4.0/24; }

router:asa3 = {
 managed;
 model = ASA;
 interface:n2 = { ip = 10.1.2.3; hardware = vlan2; }
 interface:n4 = { ip = 10.1.4.1; hardware = vlan4; }
}

router:asa4 = {
 managed;
 model = ASA;
 interface:n3 = { ip = 10.1.3.3; hardware = vlan2; }
 interface:n4 = { ip = 10.1.4.2; hardware = vlan4; }
}

area:a1 = { border = interface:asa3.n4;
            inclusive_border = interface:asa2.n2;
}
area:a2 = {anchor = network:n1; auto_border; }
group:g1 = network:[area:a2];
END

$out = <<'END';
10.1.1.0/24	network:n1
10.1.2.0/24	network:n2
END

test_group($title, $in, 'group:g1', $out);

############################################################
$title = 'Secondary interface as area border';
############################################################

$in = $topo . <<'END';
network:n4 = { ip = 10.1.4.0/24; }

router:asa3 = {
 managed;
 model = ASA;
 interface:n2 = {
  ip = 10.1.2.3; secondary:2 = { ip = 10.1.2.4; } hardware = vlan2; }
 interface:n4 = { ip = 10.1.4.1; hardware = vlan4; }
}

area:a1 = { border = interface:asa3.n2.2; }
group:g1 = network:[area:a1];
END

$out = <<'END';
10.1.1.0/24	network:n1
10.1.2.0/24	network:n2
10.1.3.0/24	network:n3
END

test_group($title, $in, 'group:g1', $out);

############################################################
$title = 'Secondary interface with name = virtual as border';
############################################################

$in = $topo . <<'END';
network:n4 = { ip = 10.1.4.0/24; }

router:asa3 = {
 managed;
 model = ASA;
 interface:n2 = {
  ip = 10.1.2.3; secondary:virtual = { ip = 10.1.2.4; } hardware = vlan2; }
 interface:n4 = { ip = 10.1.4.1; hardware = vlan4; }
}

area:a1 = { border = interface:asa3.n2.virtual; }
group:g1 = network:[area:a1];
END

$out = <<'END';
10.1.1.0/24	network:n1
10.1.2.0/24	network:n2
10.1.3.0/24	network:n3
END

test_group($title, $in, 'group:g1', $out);

############################################################
$title = 'Virtual interface as border';
############################################################

$in = $topo . <<'END';
network:n4 = { ip = 10.1.4.0/24; }

router:asa3 = {
 managed;
 model = ASA;
 interface:n2 = {
   ip = 10.1.2.3; virtual = { ip = 10.1.2.10; } hardware = vlan2; }
 interface:n4 = { ip = 10.1.4.1; hardware = vlan4; }
}

router:asa4 = {
 managed;
 model = ASA;
 interface:n2 = {
   ip = 10.1.2.4; virtual = { ip = 10.1.2.10; } hardware = vlan2; }
 interface:n4 = { ip = 10.1.4.2; hardware = vlan4; }
}

area:a1 = {
  border = interface:asa3.n2.virtual,
           interface:asa4.n2.virtual;
}

group:g1 = network:[area:a1];
END

$out = <<'END';
10.1.1.0/24	network:n1
10.1.2.0/24	network:n2
10.1.3.0/24	network:n3
END

test_group($title, $in, 'group:g1', $out);

############################################################
# Changed $topo
############################################################
$topo = <<'END';
network:n1 = { ip = 10.1.1.0/24; host:h1 = { ip = 10.1.1.10; } }
network:n2 = { ip = 10.1.2.0/24; }
network:n3 = { ip = 10.1.3.0/24; host:h3 = { ip = 10.1.3.10; } }
network:n4 = { ip = 10.1.4.0/24; }
network:n5 = { ip = 10.1.5.0/24; }

router:asa1 = {
 managed;
 model = ASA;
 routing = manual;
 interface:n1 = { ip = 10.1.1.1; hardware = vlan1; }
 interface:n2 = { ip = 10.1.2.1; hardware = vlan2; }
 interface:n3 = { ip = 10.1.3.1; hardware = vlan3; }
}

router:asa2 = {
 managed;
 model = ASA;
 routing = manual;
 interface:n2 = { ip = 10.1.2.2; hardware = vlan2; }
 interface:n3 = { ip = 10.1.3.2; hardware = vlan3; }
 interface:n4 = { ip = 10.1.4.2; hardware = vlan4; }
 interface:n5 = { ip = 10.1.5.2; hardware = vlan5; }
}
END

############################################################
$title = 'inclusive_border at areas without subset relation';
############################################################

$in = $topo . <<'END';
area:a1 = {
 inclusive_border = interface:asa1.n1;
}
area:a2 = {
 inclusive_border = interface:asa1.n2, interface:asa1.n3;
}
END

$out = <<'END';
Error: area:a2 and area:a1 must be in subset relation,
 because both have router:asa1 as 'inclusive_border'
END

test_err($title, $in, $out);

############################################################
$title = 'Missing inclusive_border at areas in subset relation';
############################################################

$in = $topo . <<'END';
area:a1 = {
 inclusive_border = interface:asa1.n1, interface:asa2.n5;
}
area:a2 = {
 border = interface:asa1.n2, interface:asa1.n3;
}

END

$out = <<'END';
Error: router:asa1 must be located in area:a2,
 because it is located in area:a1
 and both areas are in subset relation
 (use attribute 'inclusive_border')
END

test_err($title, $in, $out);

############################################################
$title = 'Empty area';
############################################################

$in = $topo . <<'END';
area:a1 = {
 inclusive_border = interface:asa1.n1, interface:asa1.n2, interface:asa1.n3;
}
END

$out = <<'END';
Warning: area:a1 is empty
END

test_warn($title, $in, $out);

############################################################
$title = 'Inconsistent definition of area in loop';
############################################################

$in = $topo . <<'END';
area:a1 = {
 border = interface:asa2.n2;
 inclusive_border = interface:asa1.n2;
}
area:a2 = {
 border = interface:asa2.n2;
}
END

$out = <<'END';
Error: Inconsistent definition of area:a1.
 It is reached from outside via this path:
 - interface:asa2.n2
 - interface:asa1.n2
Error: Inconsistent definition of area:a2 in loop.
 It is reached from outside via this path:
 - interface:asa2.n2
 - interface:asa1.n2
 - interface:asa1.n3
 - interface:asa2.n3
 - interface:asa2.n2
END

test_err($title, $in, $out);

############################################################
$title = 'ACL from inclusive area';
############################################################

# border and inclusive_border can contact at an interface.

$in = $topo . <<'END';
area:a1 = {
 inclusive_border = interface:asa1.n2, interface:asa1.n3;
}
area:a2 = {
 border = interface:asa1.n2, interface:asa1.n3;
 inclusive_border = interface:asa2.n5;
}

service:t = {
 user = network:[area:a2];
 permit src = user; dst = network:[area:a1]; prt = tcp 80;
}
END

$out = <<'END';
-- asa1
! vlan2_in
object-group network g0
 network-object 10.1.2.0 255.255.254.0
 network-object 10.1.4.0 255.255.255.0
access-list vlan2_in extended permit tcp object-group g0 10.1.1.0 255.255.255.0 eq 80
access-list vlan2_in extended deny ip any4 any4
access-group vlan2_in in interface vlan2
--
! vlan3_in
access-list vlan3_in extended permit tcp object-group g0 10.1.1.0 255.255.255.0 eq 80
access-list vlan3_in extended deny ip any4 any4
access-group vlan3_in in interface vlan3
END

test_run($title, $in, $out);

############################################################
$title = 'Router attributes from inclusive area';
############################################################

$in = $topo . <<'END';
area:a1 = {
 inclusive_border = interface:asa1.n2, interface:asa1.n3;
 router_attributes = { general_permit = icmp; }
}
END

$out = <<'END';
-- asa1
! vlan1_in
access-list vlan1_in extended permit icmp any4 any4
access-list vlan1_in extended deny ip any4 any4
access-group vlan1_in in interface vlan1
-- asa2
! vlan2_in
access-list vlan2_in extended deny ip any4 any4
access-group vlan2_in in interface vlan2
END

test_run($title, $in, $out);

############################################################
$title = 'Unreachable border';
############################################################

$in = $topo . <<'END';
area:a1 = {border = interface:asa1.n1,
                    interface:asa2.n2;}
END

$out = <<'END';
Error: Unreachable border of area:a1:
 - interface:asa2.n2
END

test_err($title, $in, $out);

############################################################
$title = 'Must not use area directly in rule';
############################################################

$in = $topo . <<'END';
area:a1 = {border = interface:asa1.n1;}
service:s1 = { user = area:a1; permit src = user; dst = network:n2; prt = tcp; }
END

$out = <<'END';
Warning: Ignoring area:a1 in src of rule in service:s1
END

test_warn($title, $in, $out);

############################################################
done_testing;
