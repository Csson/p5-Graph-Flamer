use 5.20.0;
use warnings;

package Graph::Flames::CallStack;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use Moo;
use Types::Standard -all;
use experimental qw/postderef signatures/;

has calls => (
    is => 'rw',
    isa => ArrayRef,
    required => 1,
);
has ticks => (
    is => 'ro',
    isa => Num,
    required => 1,
);

1;
