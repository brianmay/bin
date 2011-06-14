package sshpolicy;
use strict;
1;

sub check_permission($) {
        my $param = shift(@_);

        if (!defined($param->[0])) {
                return 0;
        } else {
                return 1;
        }

        return 0;
}
